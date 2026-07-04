-- Session 9 (build plan v3) — background acquisition queue.
--
-- Takes live menu acquisition OFF the request path for the slow case: fetch-menu
-- still tries to acquire LIVE within a ~1 min budget (the user waits on a
-- spinner), but if that budget is exceeded it enqueues a background job here and
-- returns "pending" ("we're working on it — check back in a few minutes"). A
-- worker Edge Function (process-menu-queue) drains this queue with a longer
-- budget and auto-estimates the new dishes; pg_cron re-kicks the worker and
-- re-enqueues stale menus for freshness.
--
-- We use a plain jobs TABLE (not pgmq, which the v3 sketch named): the plan's own
-- checks need de-dupe, status tracking, retry caps and failure records, all of
-- which are trivial with a table + a partial unique index and awkward with pgmq.

-- Extensions: pg_cron (scheduler) + pg_net (async HTTP, to call the worker fn).
create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.menu_jobs (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  -- pending: enqueued, not yet claimed. processing: a worker holds it.
  -- done: menu stored (a cache hit now serves it, so this row is inert).
  -- failed: genuine miss or retries exhausted (fetch-menu then reports not-covered).
  status        text not null default 'pending'
                  check (status in ('pending', 'processing', 'done', 'failed')),
  attempts      int  not null default 0,
  -- Last acquisition reason (mirrors menu_requests reasons: timeout / no_website /
  -- platform_only / no_menu_found) — drives retry-vs-fail and observability (S11).
  reason        text,
  last_error    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- At most one ACTIVE job per restaurant → enqueue is idempotent, concurrent
-- requests for the same place never double-process (plan check).
create unique index if not exists menu_jobs_active_uniq
  on public.menu_jobs (restaurant_id)
  where status in ('pending', 'processing');

create index if not exists menu_jobs_status_idx
  on public.menu_jobs (status, created_at);

-- RLS on, NO anon policy — same posture as menu_requests. The pending screen
-- polls fetch-menu (which reports status), so the client never reads this table
-- directly; all writes are service-role via the Edge Functions (principle #1).
alter table public.menu_jobs enable row level security;

-- Atomically claim up to `batch` pending jobs (FOR UPDATE SKIP LOCKED so two
-- concurrent worker invocations never grab the same job). Flips them to
-- 'processing' and bumps attempts; the worker resolves each to done/failed.
create or replace function public.claim_menu_jobs(batch int default 1)
returns setof public.menu_jobs
language sql
security definer
set search_path = public
as $$
  update public.menu_jobs j
     set status = 'processing',
         attempts = j.attempts + 1,
         updated_at = now()
   where j.id in (
     select id from public.menu_jobs
      where status = 'pending'
      order by created_at
      limit greatest(batch, 1)
      for update skip locked
   )
  returning j.*;
$$;

-- Only the service role (Edge Functions) may claim jobs.
revoke all on function public.claim_menu_jobs(int) from public, anon, authenticated;
grant execute on function public.claim_menu_jobs(int) to service_role;
