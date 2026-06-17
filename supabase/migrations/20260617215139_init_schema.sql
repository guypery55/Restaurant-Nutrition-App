-- Session 0: foundation only.
--
-- The real domain schema (restaurants, menus, dishes, dish_estimates) lands in
-- the Session 1 migration. This migration creates a tiny `pings` table whose
-- only purpose is the Session 0 connectivity test: prove the anon client can
-- round-trip a row to Supabase.

create table if not exists pings (
  id         uuid primary key default gen_random_uuid(),
  note       text,
  created_at timestamptz not null default now()
);

-- RLS is on. The permissive anon policies below exist ONLY for the Session 0
-- connectivity check and should be removed/tightened before any real release.
alter table pings enable row level security;

create policy "pings: anon can insert (dev only)"
  on pings for insert to anon
  with check (true);

create policy "pings: anon can read (dev only)"
  on pings for select to anon
  using (true);
