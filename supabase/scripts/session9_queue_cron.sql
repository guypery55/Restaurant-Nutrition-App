-- Session 9 (build plan v3) — pg_cron schedules for the background acquisition
-- queue. Run once via the Supabase connector (execute_sql). Idempotent: each
-- job is unscheduled (if present) then re-created. References the shared worker
-- secret by NAME from Vault (`queue_worker_secret`), so this file carries no
-- secret value and is safe to commit.
--
-- Prereqs (in migration 20260704120000_menu_jobs_queue): pg_cron + pg_net
-- enabled, public.menu_jobs + claim_menu_jobs() present; and the Vault secret
-- `queue_worker_secret` created (matches the QUEUE_WORKER_SECRET function env).

-- 1. TICK (every minute): recover stuck jobs + kick the worker when there's work.
--    fetch-menu already kicks the worker the moment it enqueues, so this tick is
--    the safety net: it drains freshness re-enqueues and re-runs jobs whose
--    worker instance died mid-flight (left 'processing').
do $$ begin perform cron.unschedule('menu-queue-tick'); exception when others then null; end $$;
select cron.schedule(
  'menu-queue-tick',
  '* * * * *',
  $job$
    update public.menu_jobs
       set status = 'pending', updated_at = now()
     where status = 'processing'
       and updated_at < now() - interval '10 minutes';

    select net.http_post(
      url := 'https://jvxqlzixqapmreghcknd.supabase.co/functions/v1/process-menu-queue',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-queue-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'queue_worker_secret')
      ),
      body := '{}'::jsonb
    )
    where exists (select 1 from public.menu_jobs where status = 'pending');
  $job$
);

-- 2. FRESHNESS (daily, 03:00 UTC): re-enqueue menus older than the freshness
--    window so coverage self-refreshes. The tick then processes them. Skips any
--    place that already has an active job (the partial unique index also guards).
do $$ begin perform cron.unschedule('menu-queue-freshness'); exception when others then null; end $$;
select cron.schedule(
  'menu-queue-freshness',
  '0 3 * * *',
  $job$
    insert into public.menu_jobs (restaurant_id)
    select m.restaurant_id
      from public.menus m
      left join public.menu_jobs j
        on j.restaurant_id = m.restaurant_id
       and j.status in ('pending', 'processing')
     where m.fetched_at < now() - interval '30 days'
       and j.id is null;
  $job$
);

select jobid, jobname, schedule, active from cron.job where jobname like 'menu-queue-%' order by jobname;
