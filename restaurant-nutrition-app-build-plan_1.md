# Restaurant Nutrition App — Build Plan

A mobile app for people curious about what they eat. The user types a restaurant
name, the app fetches and stores that restaurant's real menu, the user picks
dishes into an "assessment," and an AI returns an estimated nutrition breakdown
for each dish and for the selection combined. Built for the Israeli market
(Hebrew menus, no existing restaurant-nutrition data), AI-estimated, and
explicitly **not** for medical use.

This document is organized into **sessions**. Each session is a self-contained
unit of work you can hand to Claude Code on its own ("do Session 3"). Sessions
build on each other in order. Sessions 0–7 are the MVP; Session 8 is post-MVP.

---

## Product summary

- **Who it's for:** people interested in the nutrition of what they eat who want
  help choosing a better dish when eating out. Not for clinical/medical use.
- **What it does:** restaurant name in → real menu fetched & stored → user
  selects dishes → AI estimates calories + macros per dish and combined.
- **The honest framing:** all numbers are AI *estimates* shown as ranges, with a
  visible "AI estimate, not medical advice" disclaimer and a neutral,
  non-shaming tone.
- **The real long-term asset:** the accumulating database of Israeli-restaurant
  dishes and their estimates. No one else has this; it compounds with use.

## Non-negotiable principles (these hold across every session)

1. **The AI/API keys never live in the Flutter client.** A shipped app binary
   can be decompiled. All model calls go: client → Supabase Edge Function →
   model API → back. The same indirection is where server-side caching happens.
2. **The menu fetch must be grounded — the model never invents a menu.** "Fetch"
   means *retrieve a real source, then parse it.* The parser is instructed to
   extract only dishes present in the supplied content and to return empty if
   there is no menu. A hallucinated menu is worse than no menu.
3. **Two-layer cache for cost and consistency.** Cache the parsed *menu* per
   restaurant, and cache each *dish estimate*. A given dish must always show the
   same numbers — consistency matters more than precision for trust.
4. **Canonical key, not raw text.** Resolve the typed restaurant name through a
   Places API to a canonical place ID + location. Branches of the same chain
   differ; the place ID is the cache key.
5. **Estimates are ranges, never false-precision single numbers.** Pair them
   with qualitative tags and a one-line reasoning so the number feels grounded.
6. **Neutral tone, persistent disclaimer.** Assessments, not judgments. No
   "good/bad food." Disclaimer always visible on results.

## Tech stack

| Layer | Choice |
|---|---|
| Mobile client | Flutter (iOS + Android, Hebrew/RTL) |
| Backend / functions | Supabase Edge Functions (hold the AI key, run fetch/parse/estimate) |
| Database | Supabase Postgres (menus + dish estimates; later users + history) |
| File storage | Supabase Storage (fallback menu photos) |
| Restaurant resolution | Google Places API |
| AI | A vision-capable model for menu parsing; a text model for estimation (the Anthropic API with a vision-capable Claude model fits well; model choice is flexible) |
| Menu retrieval | Web search capability — either an LLM with a web-search tool, or a search API (SERP-style) that returns URLs you then fetch |

## Prerequisites (get these before Session 0)

- A Supabase project (URL + anon key for the client; service role key stays in functions).
- A Google Cloud project with the Places API enabled + key.
- An AI provider API key (kept only in Supabase function secrets).
- A web-search / retrieval mechanism (web-search-enabled model, or a search API key).

> Store all secret keys in Supabase function secrets / environment variables.
> The Flutter client only ever holds the Supabase URL + anon key.

## Suggested repo structure

```
/app                  # Flutter project
  /lib
    /features/search          # restaurant search & resolution
    /features/menu            # menu display + assessment basket
    /features/assessment      # results / nutrition breakdown
    /services                 # supabase client, api wrappers
    /models                   # dart data models
/supabase
  /functions
    /resolve-restaurant       # (optional) Places proxy
    /fetch-menu               # retrieve + parse + store menu
    /estimate-dishes          # per-dish nutrition estimate
  /migrations                 # SQL schema
```

---

# SESSION 0 — Project setup & foundations

**Goal:** a running Flutter app wired to Supabase, with the function scaffolding
and secrets handling in place. No features yet.

**Build:**
- Initialize the Flutter project (iOS + Android). Enable RTL / Hebrew locale
  support (`supportedLocales`, `Directionality`).
- Create the Supabase client service in Flutter using the project URL + anon key
  (loaded from a config that is **not** committed).
- Initialize the Supabase CLI in `/supabase`. Scaffold three empty Edge
  Functions: `fetch-menu`, `estimate-dishes`, and (optional) `resolve-restaurant`.
- Set up function secrets (AI key, Places key, search key) — confirm a function
  can read a secret and the client cannot.
- Add a placeholder home screen.

**Done when:**
- [ ] App builds and runs on iOS and Android, renders correctly in RTL.
- [ ] App can read/write a test row in Supabase via the anon client.
- [ ] A deployed Edge Function can read a secret and return a stub response.
- [ ] No secret keys exist anywhere in the Flutter codebase.

---

# SESSION 1 — Data model (Postgres schema)

**Goal:** the full database schema, deployed via migration.

**Build:** create a migration with the tables below.

```sql
-- Canonical restaurant entities (resolved via Places API)
create table restaurants (
  id          uuid primary key default gen_random_uuid(),
  place_id    text unique not null,   -- Google Places ID = the cache key
  name        text not null,
  address     text,
  lat         double precision,
  lng         double precision,
  created_at  timestamptz default now()
);

-- One current stored menu per restaurant (re-fetched on expiry)
create table menus (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid references restaurants(id) on delete cascade unique,
  source         text not null,        -- 'web' | 'photo'
  raw_source_url text,                  -- where it came from, if web
  fetched_at     timestamptz default now()
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

-- Cached AI nutrition estimate, one per dish (guarantees consistency)
create table dish_estimates (
  id            uuid primary key default gen_random_uuid(),
  dish_id       uuid references dishes(id) on delete cascade unique,
  calories_low  int,    calories_high int,
  protein_low   numeric, protein_high numeric,
  carbs_low     numeric, carbs_high   numeric,
  sugar_low     numeric, sugar_high   numeric,
  fat_low       numeric, fat_high     numeric,
  tags          text[],               -- e.g. {'high-protein','fried'}
  reasoning     text,                  -- one-line decomposition
  model         text,                  -- which model produced it
  created_at    timestamptz default now()
);
```

**Notes:**
- The estimate is keyed to `dish_id`, which sits under a menu under a restaurant
  — so it's effectively keyed by place + dish. Reusing the dish row is what
  delivers consistency.
- Menu freshness is the `fetched_at` timestamp (used in Session 3).
- Set up Row Level Security appropriately before any public release.

**Done when:**
- [ ] Migration applies cleanly to the Supabase project.
- [ ] All four tables exist with the relationships above.

---

# SESSION 2 — Restaurant resolution (Places API)

**Goal:** user types a name and selects a canonical restaurant (the right branch).

**Build:**
- Search box UI in `/features/search` (handles Hebrew + English input).
- Call Google Places (Autocomplete / Text Search) — ideally proxied through the
  `resolve-restaurant` function so the Places key stays server-side.
- Show candidate matches (name + address) so the user picks the correct branch.
- On selection, upsert a row in `restaurants` keyed by `place_id`; return its id.

**Notes:**
- Always disambiguate by branch — never collapse multiple locations into one.
- Bias results toward the user's location where available.

**Done when:**
- [ ] Typing a name shows real candidate restaurants with addresses.
- [ ] Selecting one creates/returns a `restaurants` row with a canonical `place_id`.
- [ ] Misspelled and Hebrew-language inputs still resolve sensibly.

---

# SESSION 3 — Menu acquisition pipeline (fetch + grounded parse + store)

**Goal:** given a resolved restaurant, return a real, parsed, stored menu — and
never an invented one.

**Build the `fetch-menu` Edge Function:**
1. **Cache check.** Look up `menus` for this `restaurant_id`. If a menu exists
   and `fetched_at` is within the freshness window (e.g. 30 days), return its
   dishes and stop.
2. **Retrieve.** Web-search using the canonical name + address. Source priority:
   (a) the restaurant's own website, (b) its Google listing, (c) delivery-platform
   pages (Wolt/10bis — last resort only; scraping them breaks their terms and is
   brittle, so do not build on them as the foundation).
3. **Fetch** the most promising page content (HTML / PDF / image).
4. **Parse** the fetched content with the grounded prompt below and store the
   result: replace the menu row and its dishes for this restaurant, set
   `source='web'`, `raw_source_url`, and a fresh `fetched_at`.
5. If no usable menu is found, return a clear "not found" signal (→ Session 4).

**Grounded parser prompt (the anti-hallucination rule lives here):**

```
You are given the raw content of a web page or image that may contain a
restaurant menu. Extract ONLY dishes that actually appear in the provided
content. Do NOT add, infer, or invent any dish from general knowledge. If the
content contains no menu, return an empty list.

For each dish return: name_he (original text, usually Hebrew), name_translit
(Latin transliteration), description (if present), section (if present),
price (number only, if present).

Respond with ONLY a JSON object: { "dishes": [ { "name_he": "...",
"name_translit": "...", "description": "...", "section": "...", "price": 0 } ] }
No prose, no markdown.
```

**Notes:**
- Start with a web-search-enabled model call for retrieval + parse in one step;
  the grounding rule still applies (it parses the *fetched* content, not memory).
- On re-fetch after expiry, the old dishes (and their cached estimates) are
  replaced. Preserving estimates by matching dish names across refreshes is a
  future optimization — fine to skip for MVP.

**Done when:**
- [ ] A resolved restaurant with a findable menu returns a structured dish list.
- [ ] The parsed menu and dishes are stored, keyed to the restaurant.
- [ ] A second request within the freshness window serves from cache (no re-fetch).
- [ ] When given content with no menu, the parser returns empty (no invented dishes).

---

# SESSION 4 — Fallback: photo-uploaded menu

**Goal:** when auto-fetch fails, let the user photograph a menu and parse it the
same way.

**Build:**
- When `fetch-menu` returns "not found," surface: "Couldn't find this menu —
  snap a photo of it?"
- Upload the photo to Supabase Storage.
- Run the **same grounded parser** on the image; store the result with
  `source='photo'`.

**Done when:**
- [ ] On fetch failure, the user is prompted to upload a photo.
- [ ] A photographed menu is parsed into dishes and stored like a fetched one.
- [ ] The dish list looks the same to the rest of the app regardless of source.

---

# SESSION 5 — Menu display & assessment basket

**Goal:** browse the stored menu and build a selection of dishes to assess.

**Build:**
- Render the menu in `/features/menu` (grouped by section, Hebrew, RTL).
- Tap a dish to add/remove it from the **assessment** basket (local state).
- A persistent "Check (N)" button that triggers Session 6.
- **No estimation happens here** — estimation is on-demand only, on button press.

**Done when:**
- [ ] The full menu renders cleanly in Hebrew/RTL.
- [ ] Users can add/remove dishes to a visible basket.
- [ ] Nothing is computed until the Check button is pressed.

---

# SESSION 6 — Nutrition estimation (per-dish + combined)

**Goal:** on button press, estimate each selected dish and the combined total.

**Build the `estimate-dishes` Edge Function:**
- Receive the selected `dish_id`s.
- For each dish: check `dish_estimates`. **Hit → reuse** (consistency). **Miss →**
  call the estimator prompt below, then store the result.
- Return per-dish estimates to the client.

**Client side:**
- Display per-dish estimates and a combined total (summing ranges → combined
  range).
- Portion scaling: a 0.5×/2× control multiplies the stored estimate locally —
  no new model call needed.

**Estimator prompt:**

```
You are estimating the nutrition of a SINGLE restaurant dish for a
general-interest app. This is NOT for medical use.

Given the dish name and description, estimate a typical single serving as
RANGES (low to high) to express uncertainty. First decompose the dish into its
likely components and portions in one short reasoning sentence, then give the
ranges. Use realistic Israeli / Middle-Eastern portion sizes.

Return ONLY this JSON:
{
  "calories_low": 0, "calories_high": 0,
  "protein_low": 0, "protein_high": 0,
  "carbs_low": 0, "carbs_high": 0,
  "sugar_low": 0, "sugar_high": 0,
  "fat_low": 0, "fat_high": 0,
  "tags": ["high-protein", "fried"],
  "reasoning": "one short sentence on the breakdown"
}
No prose, no markdown.
```

**Done when:**
- [ ] Selecting dishes and pressing Check returns per-dish estimates.
- [ ] A combined total (as a range) is shown.
- [ ] Re-checking the same dish returns identical numbers (served from cache).
- [ ] Portion adjustment rescales numbers without a new model call.

---

# SESSION 7 — Results UI, disclaimer & polish (MVP complete)

**Goal:** a trustworthy, calm results experience that completes the MVP loop.

**Build:**
- Per-dish result cards: calorie range, macro ranges, qualitative tags, and the
  one-line reasoning.
- A combined summary for the whole assessment.
- A persistent, calm disclaimer: **"AI estimate — not medical advice."**
- Neutral framing throughout (no red "bad food" styling, no shaming).
- Loading / error states for fetch and estimate steps.

**Done when:**
- [ ] The full loop works end to end: search → menu → select → estimate → results.
- [ ] The disclaimer is always visible on results.
- [ ] Tone and visuals are neutral and non-judgmental.
- [ ] You can hand it to a few people with real Israeli menus and the estimates
      feel trustworthy enough to influence a choice. **(This is the MVP's real test.)**

---

# SESSION 8 — Post-MVP: accounts, history, personalization

**Goal:** retention and the data flywheel. Only after the MVP is validated.

**Build (pick up in order of value):**
- Supabase Auth; user accounts.
- Saved/favorite restaurants and assessment history (add an `assessments` table).
- User corrections to portions/estimates fed back into the dataset (the moat).
- Later: personal goals and filtering dishes by those goals.

**Done when:**
- [ ] Users can sign in, save restaurants, and revisit past assessments.
- [ ] User corrections are captured and improve stored data.

---

## Out of scope (deliberately, for now)

- Exact/medical-grade nutrition or carb counting (the app is non-medical by design).
- Grounding estimates in external nutrition databases (decision: AI estimation only).
- Scraping Wolt/10bis as a primary data source (terms-of-service + fragility).
- Real-time menu price accuracy.

## Build order at a glance

`0 setup → 1 schema → 2 resolve → 3 fetch+parse → 4 photo fallback →
5 menu+basket → 6 estimate → 7 results (MVP) → 8 accounts/history`
