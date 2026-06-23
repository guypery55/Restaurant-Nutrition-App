-- Align the schema with build plan v2 (cheap MVP: two-tier free scraping +
-- Claude Code bulk seed under an anti-fabrication contract).
--
-- Deltas vs the Session-1 schema:
--   menus: rename raw_source_url -> source_url; add scraper + verified; widen the
--     source check to include 'claudecode' and 'manual'; add the provenance guard
--     that makes the DB itself reject a web/claudecode menu with no source URL
--     (Layer 2 of the Session-4B anti-fabrication defense).
--   new menu_requests table: the "not covered yet" capture + seed roadmap.
--
-- Safe to apply: the menus table is currently empty.

-- ---------------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------------
alter table menus rename column raw_source_url to source_url;

alter table menus add column scraper text;                         -- 'jina' | 'firecrawl' | null
alter table menus add column verified boolean not null default false;

-- Widen the allowed sources.
alter table menus drop constraint menus_source_check;
alter table menus add constraint menus_source_check
  check (source in ('web', 'claudecode', 'photo', 'manual'));

-- PROVENANCE GUARD: web/claudecode menus MUST carry the real source URL they were
-- transcribed from. photo/manual are exempt (provenance is the upload / hand entry).
alter table menus add constraint menus_provenance check (
  source in ('photo', 'manual')
  or (source_url is not null and length(source_url) > 0)
);

-- ---------------------------------------------------------------------------
-- menu_requests: restaurants we couldn't cover yet (drives the "not covered"
-- UX and tells us what to seed next). Written only by Edge Functions on the
-- service-role key — RLS on, no anon policy.
-- ---------------------------------------------------------------------------
create table menu_requests (
  id           uuid primary key default gen_random_uuid(),
  place_id     text,
  name         text,
  reason       text,        -- 'no_website' | 'platform_only' | 'no_menu_found' | 'timeout' | 'needs_pipeline'
  requested_at timestamptz not null default now()
);

alter table menu_requests enable row level security;
