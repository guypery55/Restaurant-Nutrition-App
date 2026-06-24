# Restaurant Nutrition App — Build Plan (v2, cheap MVP)

A mobile app for people curious about what they eat. The user searches an Israeli
restaurant, sees its menu, picks dishes into an "assessment," and an AI returns an
estimated nutrition breakdown per dish and combined. AI-estimated, explicitly
**not** medical.

This v2 replaces the original plan's expensive "agentic web fetch + background
queue" design. The goal now is a **cheap, working learning MVP** that opens to a
polished, instant core and grows its coverage on its own, at near-zero cost.

How it achieves that:
- **Pre-seed ~15–25 favorite restaurants offline** so the app opens warm — instant,
  reliable, great to demo.
- **Live-fetch on a miss, inline**, using *free* scraping (Jina first, Firecrawl as
  fallback). Because there is no open-ended agent loop, a single fetch fits inside
  the function time budget — no background queue needed.
- **Graceful "not covered yet"** when a restaurant has no usable online menu.

Organized into **sessions** you can hand to Claude Code one at a time. Each session
from Session 2 on ends with a **Checks** block to run before moving on; treat a
session as incomplete until its Checks pass.

---

## Product summary

- **Who it's for:** people curious about the nutrition of what they eat, who want
  help choosing a better dish when eating out. Not medical.
- **What it does:** search restaurant → see menu → select dishes → AI estimates
  calories + macros, per dish and combined, as ranges.
- **Framing:** curated guide that quietly grows. Everything it *shows* works
  instantly; misses read as "not covered yet," never as breakage.

## Non-negotiable principles (hold across every session)

1. **API keys never live in the Flutter client.** All model/scraper calls go
   client → Supabase Edge Function → API → back. The indirection is also where
   caching happens.
2. **Grounded parsing — never invent a menu.** The parser extracts only dishes
   present in the supplied content and returns empty if there is none. A
   hallucinated menu is worse than no menu.
3. **Two-layer cache for cost + consistency.** Cache the parsed menu per restaurant
   and each dish estimate. A given dish always shows the same numbers.
4. **Canonical key, not raw text.** Resolve the typed name via Google Places to a
   `place_id` + location; that is the cache key. Branches differ.
5. **Free-first scraping.** Try Jina Reader (free); only fall back to Firecrawl
   (free credits) when Jina's result fails validation. Pay nothing at MVP volume.
6. **Inline-on-miss with a hard timeout.** Acquire a missing menu within the
   request, bounded by a ~60s budget; if it trips, degrade gracefully. No queue.
7. **Estimates are ranges**, paired with tags and a one-line reasoning. Neutral,
   non-shaming tone; persistent "AI estimate, not medical advice" disclaimer.

## Tech stack

| Layer | Choice |
|---|---|
| Mobile client | Flutter (iOS + Android + web, Hebrew/RTL) |
| Backend / functions | Supabase Edge Functions (hold all keys, run fetch/parse/estimate) |
| Database | Supabase Postgres |
| File storage | Supabase Storage (only if/when photo fallback is added) |
| Restaurant resolution | Google Places API |
| Scraping (primary) | Jina Reader — free tier, browser-rendered markdown, `https://r.jina.ai/{url}` |
| Scraping (fallback) | Firecrawl — free 500 credits, headless-browser `/scrape`, `/map` for page discovery, native PDF |
| Menu parsing | Claude Sonnet 4.6 (text + vision for PDF/image menus) |
| Nutrition estimation | Claude Haiku 4.5 |
| Discovery search | A bounded web/AI search to recover an own-site URL when Places has none |

## Cost expectations (be realistic)

- **Scraping: ~$0.** Jina's free tier + Firecrawl's free credits cover hundreds of
  restaurants — far beyond a learning project.
- **LLM: a few dollars, one-time.** Parsing ~20 seeded menus (Sonnet) + pre-estimating
  a few hundred dishes (Haiku) ≈ $1–2, cached forever. Live misses add pennies each.
- After seeding, **every user tap is a free DB read.** Pay for a scraper only if this
  ever scales — which an MVP won't.

## Prerequisites

- Supabase project (URL + anon key for client; service role key stays in functions).
- Google Cloud project with Places API enabled + key.
- Firecrawl account (free tier) → API key.
- Jina key optional (works keyless at lower rate limits; a free key raises limits).
- Claude API key.
- A search capability for the discovery step (a search API free tier, or a single
  Claude call with web search — bounded to ONE query).

> All secret keys live only in Supabase function secrets. The client holds the
> Supabase URL + anon key and nothing else.

## Repo structure

```
/app                       # Flutter
  /lib
    /features/search       # restaurant search & resolution
    /features/menu         # menu display + assessment basket
    /features/assessment   # results / nutrition breakdown
    /services              # supabase client, api wrappers
    /models
/supabase
  /functions
    /resolve-restaurant    # Places proxy (done)
    /fetch-menu            # inline acquisition: discovery + scrape + parse + store
    /estimate-dishes       # per-dish nutrition estimate
  /lib/acquire             # SHARED acquisition module (used by fetch-menu AND seed)
  /scripts/seed.ts         # offline pre-seed batch
  /migrations
```

---

# SESSION 0 — Project setup & foundations

**Goal:** a running Flutter app wired to Supabase, function scaffolding, secrets in place.

**Build:**
- Initialize Flutter (iOS + Android + web). Enable RTL / Hebrew locale.
- Supabase client service in Flutter from URL + anon key (config NOT committed).
- Supabase CLI in `/supabase`. Scaffold `fetch-menu`, `estimate-dishes`,
  `resolve-restaurant`.
- Function secrets: Claude, Firecrawl, Jina (optional), Places, search. Confirm a
  function reads a secret and the client cannot.
- Placeholder home screen.

**Done when:**
- [ ] App builds/runs on iOS, Android, web; renders in RTL.
- [ ] App reads/writes a test row via the anon client.
- [ ] A deployed function reads a secret and returns a stub.
- [ ] No secret keys anywhere in the Flutter code.

---

# SESSION 1 — Data model (Postgres schema)

**Goal:** the schema, deployed via migration.

```sql
-- Canonical restaurants (resolved via Places)
create table restaurants (
  id          uuid primary key default gen_random_uuid(),
  place_id    text unique not null,   -- Google Places ID = cache key
  name        text not null,
  address     text,
  website     text,                    -- from Places, may be null or a platform link
  lat         double precision,
  lng         double precision,
  created_at  timestamptz default now()
);

-- One current stored menu per restaurant (re-fetched on expiry)
create table menus (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid references restaurants(id) on delete cascade unique,
  source         text not null check (source in ('web','claudecode','photo','manual')),
  scraper        text,                  -- 'jina' | 'firecrawl' | null
  source_url     text,
  verified       boolean default false, -- set true only after a human spot-check
  fetched_at     timestamptz default now(),
  -- PROVENANCE GUARD: web/claudecode menus MUST carry the real source URL they were
  -- transcribed from. The DB rejects a source-less row even if a tool tries to insert
  -- one. (photo/manual are exempt: their provenance is the upload / hand entry.)
  constraint menus_provenance check (
    source in ('photo','manual') or (source_url is not null and length(source_url) > 0)
  )
);

-- Dishes parsed from a menu
create table dishes (
  id             uuid primary key default gen_random_uuid(),
  menu_id        uuid references menus(id) on delete cascade,
  name_he        text not null,
  name_translit  text,
  description    text,
  section        text,
  price          numeric,
  created_at     timestamptz default now()
);

-- Cached AI nutrition estimate, one per dish (consistency)
create table dish_estimates (
  id            uuid primary key default gen_random_uuid(),
  dish_id       uuid references dishes(id) on delete cascade unique,
  calories_low  int,    calories_high int,
  protein_low   numeric, protein_high numeric,
  carbs_low     numeric, carbs_high   numeric,
  sugar_low     numeric, sugar_high   numeric,
  fat_low       numeric, fat_high     numeric,
  tags          text[],
  reasoning     text,
  model         text,
  created_at    timestamptz default now()
);

-- Requests for restaurants we couldn't cover (the "not covered yet" capture)
create table menu_requests (
  id           uuid primary key default gen_random_uuid(),
  place_id     text,
  name         text,
  reason       text,                    -- 'no_website' | 'platform_only' | 'no_menu_found' | 'timeout'
  requested_at timestamptz default now()
);
```

**Notes:**
- Estimate keyed to `dish_id` → effectively keyed by place + dish; reuse delivers consistency.
- `menu_requests` doubles as your roadmap for what to seed next.
- Set up Row Level Security before any public release.

**Done when / Checks:**
- [ ] Migration applies cleanly.
- [ ] All five tables exist with the relationships above.

---

# SESSION 2 — Restaurant resolution (Places API) — *already done*

**Goal:** user types a name and selects a canonical restaurant (the right branch).

**Build:** search box (Hebrew + English) → Google Places (proxied via
`resolve-restaurant` so the key stays server-side) → candidate list → on select,
upsert `restaurants` by `place_id`, storing `website` (may be null/platform link).

**Done when:**
- [ ] Typing a name shows real candidates with addresses.
- [ ] Selecting one upserts a `restaurants` row with canonical `place_id` (+ website if any).
- [ ] Misspelled and Hebrew inputs resolve sensibly.

**Checks (run these before moving on):**
- [ ] Hebrew search returns real candidates with addresses.
- [ ] A multi-branch chain lists distinct branches; selecting one stores that branch's `place_id`.
- [ ] Re-selecting the same place does not duplicate the row (upsert works).
- [ ] The Places key never appears client-side.
- [ ] Empty/garbage input doesn't crash.

---

# SESSION 3 — Menu acquisition (inline-on-miss, two-tier free scraping)

**Goal:** for a resolved restaurant not in the DB, acquire its menu *inline* within a
hard time budget using free scraping, store it, and degrade gracefully when there is
no usable online menu — never inventing one.

Build the acquisition logic as a **shared module** (`/supabase/lib/acquire`) so the
same code runs in `fetch-menu` (live) and in the seed script (Session 4). The
`fetch-menu` function is a thin wrapper: cache-check → call the module → return.

## The pipeline, in exact order

```
fetch-menu(restaurant):

0. CACHE CHECK
   - menu in DB for this restaurant AND fetched_at within freshness window (30d)?
     -> return its dishes. STOP. (This is the instant, free, 99% path once seeded.)

   Wrap everything below in a HARD ~60s timeout budget.
   If the budget trips at any stage -> go to step 5 (graceful fallback).

1. RESOLVE A SCRAPE URL
   a. url = restaurants.website
   b. if url is empty OR url's domain is in PLATFORM_BLOCKLIST:
        run ONE bounded discovery search (see prompt) for the OWN official site.
        Apply the validation gate: reject any result whose domain is in
        PLATFORM_BLOCKLIST. Keep the first surviving own-domain URL.
   c. if no own-domain URL survives:
        -> Case B (platform-only) or Case C (nothing). go to step 5.

2. SCRAPE — JINA FIRST, THEN CHECK
   a. Call Jina Reader:  GET https://r.jina.ai/<url>   (free; key header if set)
      -> returns markdown text.
   b. VALIDATE the Jina result with looksLikeMenu(text) (see below).
        - PASS  -> use this text. Go to step 3.
        - FAIL  -> Jina is blind here (empty shell / blocked / no menu signal).
                   Go to step 2c (Firecrawl).
   c. SCRAPE — FIRECRAWL FALLBACK (only reached when Jina failed)
        - Call Firecrawl /scrape on the same url (headless browser; returns markdown).
        - If the page clearly isn't the menu page, optionally call Firecrawl /map
          on the domain to find a menu page (look for /menu, /תפריט, "menu"),
          then /scrape that.
        - VALIDATE with looksLikeMenu(text). If it also fails -> go to step 5.
   d. If the resolved URL is a PDF or an image menu, skip Jina/Firecrawl text and
      send the file straight to Claude vision in step 3.

3. PARSE — ONE GROUNDED CLAUDE CALL
   - Feed the scraped markdown (or the image/PDF) to the GROUNDED PARSER prompt.
   - Claude returns structured dishes, or an empty list if there is no menu.
   - SECONDARY CHECK: if dishes is empty AND we used Jina text, treat it as a Jina
     miss -> fall back to Firecrawl (step 2c) once, re-parse. If still empty -> step 5.

4. STORE & RETURN
   - Upsert menus (source='web', scraper='jina'|'firecrawl', source_url, fetched_at=now)
     and replace dishes. Return dishes to the client.

5. GRACEFUL FALLBACK (no usable menu / timeout / Case B / Case C)
   - Insert a menu_requests row (place_id, name, reason).
   - Return status "not_covered" to the client -> UI shows
     "We don't have this one yet — added to our list."
   - (Optional, deferred) offer photo upload as a true last resort.
```

## `looksLikeMenu(text)` — the validation gate between Jina and Firecrawl

Return **false** (→ fall back) if any of these:
- text length below a threshold (e.g. < 400 chars) — likely an empty SPA shell.
- text matches a placeholder pattern: `/enable javascript/i`, `/loading\.\.\./i`,
  a bare cookie/consent wall, or an error page.

Return **true** (→ trust it) only if it shows a menu signal:
- a price pattern (e.g. `₪`, `\bNIS\b`, or digits followed by `ש"ח`/`שח`), OR
- menu-section keywords (`תפריט`, `מנות`, `ראשונות`, `עיקריות`, `קינוחים`,
  `menu`, `starters`, `mains`, `dessert`), OR
- at least ~5 distinct short line items.

Keep the thresholds in one place and easy to tune — you'll adjust them against real
Israeli sites.

## `PLATFORM_BLOCKLIST` (domains that are NOT an own-site)

`wolt.com`, `10bis.co.il`, `mishloha.co.il`, `tabit.cloud`, `ontopo.*`,
`rest.co.il`, `easy.co.il`, `facebook.com`, `instagram.com`, `linktr.ee`,
`google.com/maps`, `goo.gl`, `maps.app.goo.gl`. Extend as you find more.

> Scraping a restaurant's OWN public site is fine. Scraping Wolt/10bis/Instagram is
> a terms-of-service problem regardless of tool — that's why platform links route to
> "not covered yet" rather than getting scraped. Seed Wolt-only favorites by hand if
> you want them.

## Grounded parser prompt

```
You are given the raw content of a web page or image that may contain a restaurant
menu. Extract ONLY dishes that actually appear in the provided content. Do NOT add,
infer, or invent any dish from general knowledge. If the content contains no menu,
return an empty list.

For each dish return: name_he (original text, usually Hebrew), name_translit (Latin
transliteration), description (if present), section (if present), price (number
only, if present).

Respond with ONLY a JSON object: { "dishes": [ { "name_he": "...", "name_translit":
"...", "description": "...", "section": "...", "price": 0 } ] }. No prose, no markdown.
```

## Discovery search prompt (step 1b)

```
Find the OFFICIAL OWN WEBSITE of this restaurant: "<name>", <city/area>, Israel.
Return only the restaurant's own domain. Do NOT return Wolt, 10bis, Tabit, Mishloha,
Facebook, Instagram, Google Maps, or directory/aggregator links. If the restaurant
appears to have no own website (only platform or social pages), return exactly: NONE.
```

**Done when:**
- [ ] A resolved restaurant with a findable own-site menu returns structured dishes.
- [ ] Jina is tried first; Firecrawl is only called when Jina's result fails validation.
- [ ] Parsed menu + dishes stored; second request within freshness serves from cache.
- [ ] No-menu content returns empty (no invented dishes); misses log a `menu_requests` row.

**Checks (run these before moving on):**
- [ ] **Jina-first verified:** on a site Jina reads fine, confirm Firecrawl is NEVER
      called (log which scraper ran). On a heavy SPA Jina can't read, confirm it falls
      back to Firecrawl and succeeds.
- [ ] **Validation gate works:** feed `looksLikeMenu` an empty-shell string and a real
      menu string → it returns false then true. Confirm a Jina "enable JavaScript"
      shell triggers the Firecrawl fallback rather than being parsed as-is.
- [ ] **Grounding (critical):** give the parser a page with no menu (an "About" page)
      → empty list, no invented dishes. Spot-check 3–4 returned dishes against the
      source — every one must be on it.
- [ ] **Secondary check:** simulate Jina returning thin text that parses to 0 dishes →
      confirm it falls back to Firecrawl once, then re-parses.
- [ ] **Cache:** second call within freshness does not re-scrape (`fetched_at` unchanged).
- [ ] **Freshness:** set `fetched_at` ~40 days back → next call re-fetches.
- [ ] **Timeout:** simulate a slow scrape → the 60s budget trips and it falls to
      `menu_requests` + "not covered" instead of hanging.
- [ ] **No-URL path:** a restaurant with no `website` triggers the discovery search;
      a platform-only result correctly routes to "not covered" (reason `platform_only`).
- [ ] Keys (Jina/Firecrawl/Claude/search) are used only server-side.

---

# SESSION 4 — Pipeline seed (5 restaurants, proves the runtime path)

**Goal:** seed exactly ~5 restaurants through the REAL Session 3 acquisition module.
This proves the live pipeline end to end and gives you a known-good reference set.
The bulk of the catalog is seeded separately and more cheaply in Session 4B.

**Build:** `/supabase/scripts/seed_pipeline.ts` that, for each of ~5 curated restaurants:
- resolves it via Places (get `place_id` + website),
- runs the shared acquisition module (Jina → validate → Firecrawl → grounded parse),
- writes restaurant + menu (`source='web'`, `scraper`, `source_url`) + dishes,
- **pre-estimates every dish** via the Session 6 estimator and stores the results,
- logs any failure (so you hand-seed or skip).

Run once locally with the service-role key.

**Notes:**
- Pick a spread that exercises the code: a chain with an easy static site, a local
  spot, and at least one PDF/image menu to hit the vision path.
- These 5 are your ground truth — the rest of the app is built against them.

**Done when / Checks:**
- [ ] ~5 restaurants seeded with real menus AND pre-computed estimates, all via the pipeline.
- [ ] Every seeded menu row has a real `source_url` and `scraper` recorded.
- [ ] At least one PDF/image menu went through the vision path.
- [ ] Re-running is safe (upserts; no duplicates).
- [ ] Failures are logged, not silent.

---

# SESSION 4B — Bulk seed via Claude Code (cheap) — under a strict no-fabrication contract

**Goal:** seed the rest of the catalog cheaply by having **Claude Code itself** do the
find → read → transcribe work interactively (a sunk cost you're already paying),
instead of spending Jina/Firecrawl/Claude-API credits at runtime — **without ever
letting a single invented dish into the database.**

> ⚠️ This is the highest-risk session in the whole plan. Asked to "search the web and
> produce menu JSONs," an LLM will tend to *fill in plausible dishes from general
> knowledge* for any restaurant whose real menu it can't actually reach — and that
> fabricated data looks completely real once it's in your DB. Fabrication here
> silently poisons the core asset. The whole design of this session is to make
> inventing data **structurally impossible to do quietly**, not just discouraged.

## Three layers of protection (defence in depth)

**Layer 1 — the contract (instructions to Claude Code).** Hand Claude Code exactly
this block, verbatim, with your restaurant list:

```
You are seeding restaurant menus into the database. Follow these rules with ZERO
exceptions. They override any instinct to be helpful or complete.

1. TRANSCRIBE ONLY, NEVER RECALL. Insert a dish ONLY if it is literally visible on a
   real web page or PDF you actually fetched and read in this session. You must NOT
   add, guess, complete, or infer ANY dish from your own knowledge of the cuisine or
   of what a place "probably" serves. If you find yourself typing a dish you did not
   read directly from a fetched source, STOP — that is fabrication.

2. PROVENANCE REQUIRED. Every menu you insert must include the exact source_url you
   transcribed it from. No real source URL → do not insert anything for that
   restaurant.

3. SKIP AND LOG, DO NOT GUESS. If you cannot reach a real menu (JavaScript-only site,
   no findable source, blocked, PDF you can't read), DO NOT fabricate to fill the
   quota. Insert a row into `menu_requests` (reason: 'needs_pipeline') and move on.

4. FLAG EVERYTHING YOU INSERT. Set source='claudecode', record source_url, set
   fetched_at to '2000-01-01' (an old date, so the real pipeline re-acquires it
   later), and verified=false.

5. REPORT HONESTLY. At the end, list: which restaurants you seeded WITH their source
   URLs, and which you skipped and why. If you "succeeded" on every restaurant with no
   skips, you are probably fabricating — expect a real failure rate on JS-only sites.

You are held to the exact same grounding rule as the app's automated parser: only
dishes present in fetched content, empty/skip otherwise.
```

**Layer 2 — the database enforces it.** The `menus_provenance` CHECK constraint
(Session 1) makes Postgres **reject** any `source='claudecode'` row without a
`source_url`. So even if the contract is ignored, a source-less insert fails at the DB.
(It can't catch a *wrong* URL — that's what Layer 3 is for.)

**Layer 3 — mandatory human spot-check.** Nothing seeded here is trusted until you
verify a sample. After the batch, you MUST:
- Pull a random ~20% of the `source='claudecode'` menus.
- Open each one's `source_url` yourself and compare the stored dishes against the page.
- For any menu that matches the real source, set `verified=true`.
- If you find even one fabricated/mismatched menu, treat the whole batch as suspect:
  delete the unverified `claudecode` rows and re-run with a tighter list.

## Mechanics

- Give Claude Code: the target JSON shape (matching the `dishes` columns), your
  restaurant list, and the Layer-1 contract.
- It inserts via your Supabase connection (the Supabase connector) or a generated
  SQL/script you review before running.
- It does NOT touch the 5 pipeline-seeded restaurants from Session 4.
- Estimates for these dishes can be generated later by your normal `estimate-dishes`
  path on first view, or batch-run afterward — don't have Claude Code invent numbers.

## Set expectations honestly

Held to the contract, Claude Code will succeed on the easy subset (static HTML menus,
readable PDFs, menus that surface in search) and will legitimately come up empty on
the same hard JavaScript-only sites your pipeline struggles with. **Those empties are
the system working correctly.** A clean 100% success rate is the fabrication smell.

**Done when / Checks:**
- [ ] Try to insert a `source='claudecode'` row with NO `source_url` → the DB rejects
      it (the provenance constraint works).
- [ ] Every `claudecode` menu in the DB has a real, openable `source_url`.
- [ ] Claude Code's end report lists per-restaurant outcomes, including skips with reasons.
- [ ] Skipped restaurants landed in `menu_requests` (reason 'needs_pipeline'), not as
      fabricated menus.
- [ ] **Spot-check done:** you opened a ~20% sample's source URLs, confirmed the dishes
      match, and set `verified=true` on those. No mismatches found (or batch redone).
- [ ] The 5 Session-4 pipeline restaurants are untouched.

---

# SESSION 5 — Menu display & assessment basket

**Goal:** browse a stored menu and build a selection to assess.

**Build:** render menu in `/features/menu` (sections, Hebrew/RTL); tap to add/remove
dishes to an assessment basket (local state); a persistent "Check (N)" button.
**No estimation here** — it's on-demand (and for seeded dishes it's already cached).

**Done when:**
- [ ] Menu renders cleanly in Hebrew/RTL, grouped by section.
- [ ] Add/remove dishes updates a visible basket.
- [ ] Nothing computes until Check is pressed.

**Checks (run these before moving on):**
- [ ] Hebrew renders right-to-left and correctly aligned.
- [ ] Basket count updates accurately on add/remove.
- [ ] Network tab shows zero estimation calls while adding to the basket.
- [ ] Check button disabled when empty; shows count when populated.

**Implemented (2026-06-24):** `lib/models/dish.dart`, `lib/services/menu_service.dart`
(`fetch-menu` wrapper → `MenuResult.found/.notCovered`), `lib/features/menu/menu_screen.dart`
(FutureBuilder; loading / found / not-covered / error+retry; dishes grouped by section in
first-appearance order; tap toggles a local basket; persistent "בדיקה (N)" bar disabled when
empty), and a wired `home_screen` (search → push MenuScreen). No estimation on this screen —
Check only navigates. Plain Flutter local state, no state-mgmt package.

---

# SESSION 6 — Nutrition estimation (per-dish + combined)

**Goal:** on Check, estimate each selected dish and the combined total — reusing
cached estimates so numbers never wobble.

**Build `estimate-dishes`:** receive `dish_id`s → for each, check `dish_estimates`
(**hit → reuse**; **miss → call estimator, store**) → return per-dish estimates.
This is the same function the seed script calls in Session 4.

**Client:** show per-dish estimates + a combined total (sum the ranges). Portion
scaling (0.5×/2×) multiplies the stored estimate locally — no new model call.

**Estimator prompt:**

```
You are estimating the nutrition of a SINGLE restaurant dish for a general-interest
app. This is NOT for medical use.

Given the dish name and description, estimate a typical single serving as RANGES
(low to high) to express uncertainty. First decompose the dish into its likely
components and portions in one short reasoning sentence, then give the ranges. Use
realistic Israeli / Middle-Eastern portion sizes.

Return ONLY this JSON:
{ "calories_low":0,"calories_high":0,"protein_low":0,"protein_high":0,
  "carbs_low":0,"carbs_high":0,"sugar_low":0,"sugar_high":0,"fat_low":0,"fat_high":0,
  "tags":["high-protein","fried"], "reasoning":"one short sentence" }
No prose, no markdown.
```

**Done when:**
- [ ] Check returns per-dish estimates and a combined range.
- [ ] Re-checking the same dish returns identical numbers (cache).
- [ ] Portion adjustment rescales without a model call.

**Checks (run these before moving on):**
- [ ] Response matches the estimator JSON shape for every dish.
- [ ] **Consistency (critical):** checking the same dish twice → identical numbers,
      and the second check makes no model call.
- [ ] Seeded dishes return instantly (already cached from Session 4).
- [ ] Combined total = sum of per-dish ranges (verify by hand on two dishes).
- [ ] Portion 2× exactly doubles, with no network request.
- [ ] A fresh dish writes a `dish_estimates` row.
- [ ] Malformed model output is caught and handled, never shown as garbage.

**Implemented (2026-06-24):** backend `estimate-dishes` + shared `_shared/estimate` (Haiku,
one-per-dish cache) were built/deployed earlier; this session wired the client.
`lib/models/dish_estimate.dart` (parses the row; `.scaled(factor)` is LOCAL portion math —
no model call), `lib/services/estimate_service.dart` (`estimate(dishIds)` → `Map<dishId, est>`),
and the real `lib/features/assessment/assessment_screen.dart`: calls the estimator on open,
shows a combined-total card (summed ranges) + per-dish cards (calorie headline, macro grid,
reasoning, ½×/1×/2× portion selector), graceful "couldn't estimate" line per dish, persistent
"אינה ייעוץ רפואי" disclaimer. Live-verified against the deployed function (correct shape,
`cached:true`).

**Added beyond the original plan (2026-06-24):**

- **Precise mode** — a pinned טווח / מדויק (Range / Precise) toggle on the assessment screen.
  In precise mode every low–high figure (per-dish calories + macros AND the combined total)
  collapses to its midpoint average. Display-only; estimates and portion math are untouched.

- **Macro ratings (calorie-share)** — `lib/models/macro_rating.dart`: `rateMacros({calories,
  protein, carbs, sugars, fat})` rates each macro low/moderate/high by its **share of total
  CALORIES** (never weight). 4 kcal/g for protein/carbs/sugars, 9 for fat;
  `pct = grams*kcal/calories*100`. Thresholds: protein high≥20/mod≥12 (higher better); carbs
  high≥65/mod≥45 (neutral); sugars high≥10/mod≥5 (lower better); fat high≥35/mod≥20 (lower
  better). Each rating carries a `direction` + `isPositive`. Divide-by-zero guarded
  (calories≤0 → 0% / low). Fully unit-tested in `test/macro_rating_test.dart` (boundaries
  incl. exactly-20%-protein / 10%-sugar, plus the zero-calorie guard).

- **Positives-only dish highlights** — the dish card now shows ONLY good flags (green chips),
  replacing the raw estimate tags: a dessert surfaces דל בסוכר / דל בשומן when genuinely low;
  mains & starters surface עשיר בחלבון when genuinely high in protein. Nothing shown when
  there's nothing good to say — no warnings, no red (neutral, non-shaming framing). Ratings
  use range midpoints; share is portion-invariant so highlights are stable across ½×/2×.

---

# SESSION 7 — Results UI, "not covered yet", disclaimer & polish (MVP complete)

**Goal:** a trustworthy, calm experience that completes the loop and handles misses well.

**Build:**
- Per-dish cards: calorie range, macro ranges, tags, the one-line reasoning.
- Combined summary.
- **Miss handling:** when `fetch-menu` returns "not covered", show a friendly
  "We don't have this one yet — added to our list" state (this is the curated-guide
  framing; misses must never look like crashes).
- Persistent disclaimer: **"AI estimate — not medical advice."**
- Neutral framing (no red "bad food" styling, no shaming).
- Loading / error states for fetch and estimate.

**Done when:**
- [ ] Full loop works end to end on a seeded restaurant: search → menu → select →
      estimate → results.
- [ ] A live miss shows the graceful "not covered yet" state, not an error.
- [ ] Disclaimer always visible on results.
- [ ] Tone/visuals neutral and non-judgmental.

**Checks (run these before moving on):**
- [ ] End-to-end run on a phone and on Chrome (web), no dead ends.
- [ ] Search a restaurant you DON'T have → confirm the inline fetch runs, and either
      fills the menu or lands on a clean "not covered yet" (with a `menu_requests` row).
- [ ] Kill the network mid-fetch and mid-estimate → clear error states, retry, no crash.
- [ ] Disclaimer cannot be permanently scrolled away.
- [ ] Tone review: no shaming language or "bad" styling anywhere.

---

# PHASE 2 — deferred (clearly optional; only if you want to learn each)

- **Decoupled acquisition pipeline:** move live fetch off the request path with
  Supabase Queues (pgmq) + pg_cron worker + a "pending, check back" UX. Worth
  learning; unnecessary while inline-on-miss fits the budget.
- **Accounts & history:** Supabase Auth, saved restaurants, past assessments, user
  corrections feeding back into the data. Add RLS tests.
- **Photo fallback as a real feature:** Storage upload → same grounded vision parse,
  flagged low-confidence. Only for restaurants with no online menu at all.
- **Platform menus (Wolt/10bis):** a deliberate terms-of-service decision; default
  is to keep routing these to "not covered yet."

## Build order at a glance

`0 setup → 1 schema → 2 resolve (done) → 3 acquisition module + inline fetch
(Jina→check→Firecrawl) → 4 pipeline seed (5) → 4B Claude Code bulk seed (grounded) →
5 menu+basket → 6 estimate → 7 results + not-covered (MVP)  →  Phase 2 if desired`
