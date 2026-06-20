-- Session 1: the domain schema.
--
-- Four tables that model the core loop:
--   restaurants  -> canonical place resolved via Google Places (the cache key)
--   menus        -> one current stored menu per restaurant (re-fetched on expiry)
--   dishes       -> dishes parsed from a menu
--   dish_estimates -> one cached AI nutrition estimate per dish (consistency)
--
-- Writes are performed server-side by Edge Functions using the service-role key,
-- which bypasses RLS. The Flutter client (anon role) only ever READS this data,
-- so every table enables RLS with an anon SELECT policy and no anon write policy.
-- See principle #1 in the build plan: keys and writes stay on the server.

-- ---------------------------------------------------------------------------
-- restaurants: canonical restaurant entities (resolved via Places API)
-- ---------------------------------------------------------------------------
create table restaurants (
  id          uuid primary key default gen_random_uuid(),
  place_id    text unique not null,   -- Google Places ID = the cache key
  name        text not null,
  address     text,
  lat         double precision,
  lng         double precision,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- menus: one current stored menu per restaurant (re-fetched on expiry)
-- ---------------------------------------------------------------------------
create table menus (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references restaurants(id) on delete cascade unique,
  source         text not null,        -- 'web' | 'photo'
  raw_source_url text,                  -- where it came from, if web
  fetched_at     timestamptz not null default now(),
  constraint menus_source_check check (source in ('web', 'photo'))
);

-- ---------------------------------------------------------------------------
-- dishes: dishes parsed from a menu
-- ---------------------------------------------------------------------------
create table dishes (
  id             uuid primary key default gen_random_uuid(),
  menu_id        uuid not null references menus(id) on delete cascade,
  name_he        text not null,
  name_translit  text,
  description    text,
  section        text,
  price          numeric,
  created_at     timestamptz not null default now()
);

-- Dishes are almost always queried by their menu ("show me this menu's dishes").
create index dishes_menu_id_idx on dishes(menu_id);

-- ---------------------------------------------------------------------------
-- dish_estimates: cached AI nutrition estimate, one per dish (consistency)
-- ---------------------------------------------------------------------------
create table dish_estimates (
  id            uuid primary key default gen_random_uuid(),
  dish_id       uuid not null references dishes(id) on delete cascade unique,
  calories_low  int,     calories_high int,
  protein_low   numeric, protein_high  numeric,
  carbs_low     numeric, carbs_high    numeric,
  sugar_low     numeric, sugar_high    numeric,
  fat_low       numeric, fat_high      numeric,
  tags          text[],                -- e.g. {'high-protein','fried'}
  reasoning     text,                  -- one-line decomposition
  model         text,                  -- which model produced it
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- RLS is enabled on every table. The anon role gets read-only access so the
-- client can browse restaurants, menus, dishes, and estimates. No anon write
-- policies exist: all inserts/updates run through Edge Functions with the
-- service-role key, which bypasses RLS entirely.
-- ---------------------------------------------------------------------------
alter table restaurants    enable row level security;
alter table menus          enable row level security;
alter table dishes         enable row level security;
alter table dish_estimates enable row level security;

create policy "restaurants: anon can read"
  on restaurants for select to anon using (true);

create policy "menus: anon can read"
  on menus for select to anon using (true);

create policy "dishes: anon can read"
  on dishes for select to anon using (true);

create policy "dish_estimates: anon can read"
  on dish_estimates for select to anon using (true);
