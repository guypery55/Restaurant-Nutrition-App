# Restaurant Nutrition App — Build Plan v4 (speed, perceived speed, and depth)

> **Status: the active roadmap.** Replaces v2 (MVP record, Sessions 0–7) and v3
> (trust + queue, Sessions 8–9) — both live in git history (`c350ea0` and
> earlier). This plan came out of a full-codebase latency & UX audit
> (2026-07-04): five parallel readers over the client, edge functions, and DB,
> every finding verified against the source line-by-line.
>
> **The v4 thesis: the user should see usable results as fast as physically
> possible, and every unavoidable wait should feel intentional.** Speed first,
> then pipeline depth, then quality ops.

## Where we are (end of v3 S9)

Working loop: search → resolve → menu → basket → AI nutrition estimate
(per-dish + combined, ranges/precise, portions, positives-only highlights).
Coverage is **organic**: cache hit → instant; miss → live try (~55s budget) →
on timeout, background queue (`menu_jobs` + `process-menu-queue` worker +
pg_cron) with auto-estimate, client auto-polls. Estimator is Haiku, per-dish
cached, self-consistency guardrail (S8, prompt-level). Catalog is consistent
Hebrew (hand-backfilled 2026-07-01). All keys server-side. Anonymous, no-login.

**Standing principles (unchanged from v2/v3):**
1. All API keys stay server-side; the client only calls our edge functions.
2. Grounded everywhere — never invent a dish, never fabricate a menu.
3. Estimates are cached per dish — numbers never wobble.
4. A miss reads as a gap in a growing guide, never as breakage. Calm Hebrew,
   positives-only framing, no shaming.
5. Launch, accounts, and abuse/cost guards remain **parked** until we choose to
   launch (v3 decisions, 2026-06-30/07-01, still stand — see "Parked" below).

## Where the time goes today (audit summary)

Measured against the code as deployed (commit `c350ea0`):

- **Live acquisition** stacks sequential fallbacks: Jina 25s → Firecrawl 25s
  per page, a serial 15s `firecrawlMap`, a serial zero-dish re-scrape+re-parse,
  and a **Sonnet** parse generating up to 6,000 tokens of JSON with **no
  timeout** — so JS-heavy sites reliably blow the 55s budget and drop the user
  to "pending" when live results were achievable. Discovery (30s Claude
  web_search) is re-paid on every retry because the found URL is never saved.
- **Assessment** is all-or-nothing: one FutureBuilder hides every result behind
  the slowest Haiku call; nothing is warmed while the user browses; a menu
  refresh cascades away the whole estimate cache (`menus` delete → `dishes` →
  `dish_estimates`).
- **The queue** is strict FIFO, one job at a time (up to 110s each), no
  priority — a waiting user can queue behind the daily freshness batch; the
  worker idles up to 60s between generations; stuck-job recovery waits 10
  minutes for a worker that can only live ~150s.
- **The hot cached path** (99% of traffic) makes 3 sequential DB round trips,
  and the client re-fetches menus and immutable estimates on every navigation.

Sessions 10–13 remove these. Session 14 is v3's pipeline-depth work (carried
over intact). Session 15 is v3's quality ops (carried over intact).

---

## Session arc

- **S10 — Acquisition speed** *(server-only; no UX change; biggest raw wins)*
- **S11 — Hot path & client responsiveness** *(client + one server tweak; small
  deliberate UX changes)*
- **S12 — Instant assessment** *(prefetch + progressive results; the biggest
  perceived-speed win; visible UX change)*
- **S13 — Queue: user-first, no dead time** *(DB + worker; UX unchanged, waits
  shorten)*
- **S14 — Pipeline & scraper depth + Hebrew normalization** *(v3's S10, carried
  over verbatim in scope)*
- **S15 — Quality ops: verification + feedback + observability** *(v3's S11,
  carried over verbatim in scope)*

Each session is independently deployable and independently verifiable. Do them
in order — S10 makes S13's queue faster too (the worker runs the same
pipeline), and S12 leans on S11's client caches.

**Expected net effect (order-of-magnitude, verify per session):** cached menu
loads ~300ms faster and instant on re-open; live acquisitions 25–50s faster
with many current "pending" cases becoming live results; first usable
assessment numbers in ~1s instead of 5–15s; a waiting user's worst-case queue
delay drops from minutes-behind-a-batch to next-slot.

---

## Session 10 — Acquisition speed (server-only)

**Goal:** cut 25–50s from every cold acquisition so the 55s live try succeeds
far more often. Everything here is inside `supabase/functions/` — **zero UI
changes, zero UX decisions**. The user just sees live menus where they used to
see the pending screen.

**UX change required: none.** (Faster is the feature.)

### Build

1. **Parse on Haiku, with a timeout** — `_shared/acquire/parse.ts`
   - Line 7: split the model env. `const PARSE_MODEL =
     Deno.env.get("PARSE_MODEL") ?? "claude-haiku-4-5";` — stop reusing
     `MENU_MODEL` (which stays for discovery). Grounded JSON extraction is
     exactly Haiku's use case; the file's own header says "fast and cheap".
   - `callParse` (line 71): replace the bare `fetch` with `fetchWithTimeout`
     (import from `./scrape.ts`), capped at **25_000ms** — today a hung
     Anthropic call silently eats the whole live budget.
   - Keep `max_tokens: 6000` and the grounded prompt untouched (do NOT touch
     grounding).
   - **Input cap:** in `parseMenuText`, truncate `content` to the first
     **80_000 chars** before building the message. Real menus are never that
     big; the tail is nav/footer noise that costs input tokens and seconds.
   - *Risk check:* before switching the default, run one A/B on a seeded menu
     (e.g. Thai House source page): parse with Sonnet and with Haiku, diff dish
     counts and names. Accept Haiku if it captures ≥95% of Sonnet's dishes with
     no invented items. If it fails, keep Sonnet for the worker (`MENU_MODEL`)
     and Haiku for the live path only.

2. **Hedged scraping instead of chained fallback** — `_shared/acquire/index.ts`
   `scrapeBest` (lines 222–240)
   - Today: await Jina (25s timeout) → only then try Firecrawl (25s) → worst
     case 50s for ONE page. Replace with a hedge:
     - Fire `jinaScrape(url)` immediately.
     - Start `firecrawlScrape(url)` after a **5s** delay *unless* Jina has
       already returned text that passes `looksLikeMenu`.
     - Return the **first** result that passes `looksLikeMenu`; if both
       complete and fail the gate, return empty as today.
   - Implementation shape: two promises + a small `firstPassing()` helper that
     resolves on the first gate-passing result and lets the loser settle in the
     background (both are already individually timeout-capped in `scrape.ts`;
     no AbortController threading needed — ignore the loser).
   - Keep per-call timeouts in `scrape.ts` as they are (25s/25s/15s).

3. **Skip the zero-dish secondary retry on the live path** —
   `_shared/acquire/index.ts` `scrapeAndParse` (lines 192–218)
   - The "Jina parsed to 0 dishes → re-scrape via Firecrawl → re-parse" chain
     can stack >85s onto one page inside a 55s budget, and one bad page drags
     the whole `Promise.all` into timeout.
   - Thread the budget through: `acquireMenu` already receives `budgetMs` —
     pass a `deadline` (epoch ms) down `runPipeline` → `scrapeAndParse`, and
     only run the secondary retry when `deadline - Date.now() > 35_000`. The
     background worker (110s budget) keeps the retry; the live try (55s)
     effectively skips it. No behavior change for the queue path.

4. **Run `firecrawlMap` concurrently with the landing scrape** —
   `_shared/acquire/index.ts` (lines 109–117)
   - `firecrawlMap(origin, "menu")` needs only the origin, known before the
     landing scrape starts. Change to:
     ```ts
     const mapP = origin ? firecrawlMap(origin, "menu") : Promise.resolve([]);
     const landing = await scrapeBest(url);
     const mapped = await mapP;
     ```
   - Saves up to 15s on every acquisition (live AND worker).

5. **Persist the discovered website** — `_shared/acquire/index.ts`
   `runPipeline` (after line 94)
   - `discoverOwnSite` costs up to 30s of Claude web_search and the result is
     thrown away — every worker retry and every post-cooldown revisit re-pays
     it. After a successful discovery returns a non-platform URL:
     ```ts
     await db.from("restaurants").update({ website: url }).eq("id", r.id);
     ```
   - Idempotent, grounded (it's the restaurant's own site), and makes retries
     start scraping immediately.

6. **Jina rate-limit hygiene** — config task, not code
   - The pipeline fires up to 9 concurrent Jina requests; keyless Jina
     rate-limits aggressively and each 429 converts into a slow Firecrawl
     fallback. Set `JINA_API_KEY` in function secrets
     (`supabase secrets set JINA_API_KEY=...`). The code already sends it when
     present (`scrape.ts:34-36`).

### Checks

- **Before/after timing** on the same 3 test sites (one clean HTML menu, one
  JS-heavy, one multi-page) using `fetch-menu` with `debug: true` and
  `force: true`: record wall time and `trace.pages`. Target: JS-heavy site
  completes the live try inside 55s where it previously went pending.
- Haiku parse A/B recorded (dish counts, no inventions) before flipping the
  default.
- A discovery-path restaurant (no `website`) acquires once, and the row's
  `website` is filled afterward; the second `force: true` run skips discovery
  entirely (visible in timing).
- Worker path unchanged: enqueue a heavy site, confirm it still acquires with
  the secondary retry available (trace shows it when needed).
- Zero fabrication: no-menu site still returns `not_covered` + `menu_requests`
  row.

**OUTCOME (built + deployed + live-verified 2026-07-06):**

*All five items shipped* (`parse.ts`, `acquire/index.ts`, `discover.ts`);
`fetch-menu` + `process-menu-queue` deployed. Two deviations/additions, both
found live:

- **PARSE_TIMEOUT_MS = 40s, not the planned 25s** — the timeout is anti-hang,
  not pacing, and a legitimately large menu's JSON can exceed 25s even on
  Haiku; 40s still can't eat a whole budget.
- **Discovery was silently broken in two ways** (surfaced because persistence
  finally made its output visible): (a) every failure path returned null with
  zero logging — error logging added; (b) the URL regex leaked markdown
  emphasis into the URL (a bold `**https://www.taizu.co.il**` answer persisted
  the trailing `**` and would have poisoned `restaurants.website` forever) —
  regex now excludes `*`/`]` and strips trailing punctuation.

*A/B gate (same site, same 9 pages, minutes apart):* McDonald's IL —
**Haiku 26.8s / 27 dishes** vs **Sonnet 39.8s / 27 dishes, identical names**
→ 100% capture, zero inventions, ~33% faster. Haiku default locked. June
baseline for the same site (Sonnet + sequential scraping): ~40s.

*Worker path:* Thai House test job claimed → acquired → **auto-estimated 24
dishes → done in ~82s, 1 attempt** (S9 reference: ~105s for 57 dishes).

*Discovery persistence:* throwaway with `website=null` named "טאיזו" →
resolved `https://www.taizu.co.il` (clean) → **verified written to
`restaurants.website`** → subsequent runs skip the ~30s search by code path.
Generic names ("בית תאילנדי") honestly returned NONE across retries — misses
logged as `no_website`, nothing fabricated, no jobs enqueued.

*Zero fabrication re-verified:* every miss logged to `menu_requests` with a
reason; no menu stored on any zero-dish run; catalog restored to exactly
6 menus / 251 dishes / 251 estimates; all test rows cleaned.

*Known limits recorded honestly:*
- **Keyless Jina + Firecrawl rate-limit storms** are real: back-to-back force
  runs on one site produced two all-pages-blank runs (even Firecrawl /scrape
  429'd while /map worked). Production rarely force-refetches one site
  repeatedly, but the fix is cheap → **USER ACTION: set `JINA_API_KEY`**
  (`supabase secrets set JINA_API_KEY=...`; code already sends it).
- Taizu/McDonald's JS-grid product pages still parse 0 dishes, and Thai House
  yielded 24/67 dishes from its one readable page — that's S14 (scraper
  depth), unchanged by this session.
- First post-deploy request can still be served by the previous function
  version (observed v18 handling the first call after v19 deployed) — wait a
  few seconds after deploying before measuring.

---

## Session 11 — Hot path & client responsiveness

**Goal:** make the 99% path (cached menus) and all navigation feel instant, and
make every unavoidable wait honest — staged, skeletoned, never hang-shaped.

**UX changes required: yes, four deliberate ones** (each listed with its item).

### Build

1. **Collapse fetch-menu's cache hit to one round trip** —
   `supabase/functions/fetch-menu/index.ts` (lines 49–87). *UX change: none.*
   - Today: restaurants select → menus select → dishes select, strictly serial.
   - Run the restaurant lookup and the menu+dishes lookup **in parallel**, with
     the dishes embedded:
     ```ts
     const [{ data: restaurant }, { data: existingMenu }] = await Promise.all([
       db.from("restaurants").select("id, place_id, name, address, website")
         .eq("id", restaurantId).single(),
       db.from("menus")
         .select("id, fetched_at, source, scraper, source_url, verified, dishes(*)")
         .eq("restaurant_id", restaurantId).maybeSingle(),
     ]);
     ```
   - `dishes(*)` uses the existing `dishes_menu_id_idx`. The 404 check moves
     after the `Promise.all`. Cuts ~2 round trips (~100–300ms) off every
     cached load.

2. **Client-side menu cache** — `app/lib/services/menu_service.dart`.
   *UX change: yes — re-opening a menu renders instantly with no spinner.*
   - Add to `MenuService`: `static final Map<String, (MenuResult, DateTime)>
     _cache = {};` with TTL **15 minutes**. Cache **only** `found` results.
   - `fetchMenu(restaurantId, {bool force = false})`: on a fresh cache hit
     return synchronously; on miss/stale, fetch and populate.
   - `MenuScreen._load`: if the service returns instantly (cached), never set
     `_loading = true` — no spinner flash. The existing `_reload` passes
     `force: true` (manual refresh stays honest).

3. **Client-side estimate cache** — `app/lib/services/estimate_service.dart`.
   *UX change: yes — repeat/edited basket checks render instantly.*
   - Estimates are immutable by design ("numbers never wobble"), so cache them
     forever in-session: `static final Map<String, DishEstimate> _cache = {};`
   - `estimate(ids)`: split into cached vs missing; invoke the edge function
     only for missing ids; merge into the cache; return the union. An
     unchanged repeat Check becomes a zero-network render; editing the basket
     by one dish pays for one dish.

4. **Timeouts + staged loading copy** — all four `functions.invoke` call sites.
   *UX change: yes — new staged Hebrew loading copy; hangs become retries.*
   - Wrap in `.timeout()`: autocomplete **10s**, select **15s**,
     fetch-menu **70s** (covers the 55s server budget + overhead),
     estimate-dishes **60s**. On `TimeoutException`, surface the existing
     retry UIs (`_MenuError`, `_EstimateError`, search snackbar).
   - `_MenuLoading` (menu_screen.dart): staged copy so the long cold fetch
     reads as progress, not breakage —
     - 0s: `טוען תפריט…`
     - after 6s: `מחפשים את התפריט באתר המסעדה…`
     - after 20s: `עוד רגע — קוראים את התפריט 👨‍🍳`
   - Implement with a `Timer.periodic`-driven index in a stateful
     `_MenuLoading`; cancel on dispose.

5. **Skeletons instead of bare spinners** — `menu_screen.dart`,
   `assessment_screen.dart`. *UX change: yes — shaped loading states.*
   - `_MenuLoading`: 2 section-header blocks + 6 dish-tile placeholder rows
     (grey rounded boxes, gentle opacity pulse — plain `AnimatedOpacity` loop,
     no new package). Keep the staged text above the skeleton.
   - `_EstimateLoading`: one skeleton `_DishCard` **per selected dish** (count
     is known from `widget.dishes`) + a skeleton combined card. This becomes
     the base for S12's progressive fill.

6. **Overlap select with navigation** — `search_screen.dart` (lines 78–91),
   `menu_screen.dart`. *UX change: yes — one continuous loading state instead
   of modal → screen-switch → second spinner.*
   - On candidate tap, navigate **immediately** to `MenuScreen`, passing the
     `RestaurantCandidate` (name/address are already known for the AppBar).
   - `MenuScreen` gains a constructor variant (`MenuScreen.fromCandidate`)
     that runs `RestaurantService.select(placeId)` → `fetchMenu(...)` inside
     its single existing loading state. Remove the `_selecting` modal overlay
     from the search screen.
   - Failure of `select` lands in the existing `_MenuError` retry UI.

7. **Poll ladder for the pending screen** — `menu_screen.dart` (lines 35–88).
   *UX change: yes — auto-poll covers ~5 minutes (matches the "few minutes"
   copy) instead of dying at 2.*
   - Replace the flat 15s×8 with a backoff ladder:
     `[8, 8, 10, 15, 20, 30, 30, 45, 60, 60]` seconds (~4.8 min, 10 requests
     vs 8 today). The worker is kicked immediately on enqueue and many jobs
     finish 10–30s after handoff — the first re-check at 8s catches them;
     the long tail covers heavy-site retries. After the ladder, the existing
     manual `בדקו שוב` button takes over unchanged.

### Checks

- Cached menu open (seeded restaurant): server logs show one DB round trip for
  menu+dishes; client renders with no spinner on second open within TTL.
- Repeat Check with an unchanged basket makes **zero** network calls (verify
  with the network log / debugger).
- Kill network mid-fetch: every screen lands in a retry UI within its timeout —
  nothing spins forever.
- Cold restaurant: staged copy advances; skeletons render; no layout jump when
  real data lands.
- Search tap → menu: exactly one continuous loading state; select failure shows
  the menu error retry, and retry re-runs select.
- Pending flow: first re-check ~8s after handoff; menu auto-appears when the
  worker lands it; ladder exhausts into the manual button. `flutter analyze`
  clean.

---

## Session 12 — Instant assessment (prefetch + progressive results)

**Goal:** the single biggest *perceived* speed win. The user should almost never
watch an estimation spinner: estimates are warmed while they browse, and
whatever isn't ready streams in per-dish instead of blocking everything.

**UX changes required: yes — this session visibly changes the assessment
screen's loading behavior (for the better). Details per item.**

### Build

1. **Prefetch on selection** — `menu_screen.dart` `_toggle`,
   `estimate_service.dart`. *UX change: none visible directly — it's what makes
   Check feel instant.*
   - When a dish is **added** to the basket, fire-and-forget
     `EstimateService.estimate([dish.id])`. By the time the user finishes
     picking and taps בדיקה, the estimates are server-computed and sitting in
     the S11 client cache.
   - Dedupe in the service: keep `static final Map<String,
     Future<Map<String, DishEstimate>>> _pending = {};` so a tap→untap→tap
     doesn't double-invoke, and the assessment screen awaits the same future
     instead of re-requesting.
   - Cost note: this estimates only dishes the user explicitly selected — no
     speculative whole-menu spend. (Whole-menu prefetch is deliberately NOT
     done: queue-acquired menus are already auto-estimated by the worker, and
     estimating every viewed menu would multiply Haiku spend for dishes nobody
     checks.)

2. **Auto-estimate after a LIVE acquire** — `fetch-menu/index.ts`.
   *UX change: none visible — removes the one remaining cold-estimate case.*
   - The queue worker already auto-estimates; the live path doesn't. After a
     successful live acquire (the `result.status === "found"` branch), kick
     estimation in the background so it never delays the response:
     ```ts
     const ids = result.dishes.map((d) => d.id).filter(Boolean);
     const est = estimateDishes(db, ids).catch((e) =>
       console.error("live auto-estimate:", e));
     if (rt?.waitUntil) rt.waitUntil(est);
     ```
     (same `EdgeRuntime.waitUntil` pattern as `kickWorker`).
   - With this + prefetch-on-tap, every path into assessment is warm.

3. **Progressive assessment rendering** — `assessment_screen.dart`.
   *UX change: yes — cards appear one by one; the combined card fills last.*
   - Replace the single `FutureBuilder` with per-dish state:
     `final Map<String, DishEstimate?> _estimates = {};` (null = still
     loading). In `initState`, fan out `EstimateService.estimate` in **chunks
     of 3** dish ids, concurrently; as each chunk future completes, `setState`
     merges results.
   - Render immediately: every `_DishCard` shows real name + portion selector
     at once, with the S11 skeleton body until its estimate lands; a dish whose
     estimate failed shows the existing calm "לא הצלחנו להעריך" line.
   - `_CombinedCard`: while any dish is loading, show the running subtotal
     with a small inline `מתעדכן…` label; when all land, the label disappears.
     (Never show a wrong-looking final total silently — the label is the
     honesty marker.)
   - The full-screen `_EstimateError` remains only for the case where *every*
     chunk failed; single-chunk failures degrade to per-card fallbacks.

4. **Estimator plumbing** — `_shared/estimate/index.ts`. *UX change: none.*
   - **Worker pool over waves** (lines 120–137): replace the fixed
     5-per-wave loop with 5 workers pulling from a shared index — a slow dish
     no longer stalls the next four. Keep `MAX_CONCURRENT = 5`.
   - **Bulk insert**: collect fresh rows and store once at the end:
     `db.from("dish_estimates").upsert(rows, { onConflict: "dish_id",
     ignoreDuplicates: true })` — replaces N sequential awaited inserts (which
     also makes the concurrent-users duplicate race harmless by construction).
   - **Prompt caching** (line 199): the ~650-token static prompt →
     `system: [{ type: "text", text: ESTIMATOR_PROMPT, cache_control:
     { type: "ephemeral" } }]`. Warm across the pool and across a whole-menu
     worker run.
   - **One bounded retry** in `estimateOne`: on 429/5xx/overloaded, wait
     `min(retry-after, 2s)` and retry once. Converts intermittent blank cards
     into results ~2s later; never multiplies worst-case latency by more than
     one bounded retry.

5. **Stop wiping the estimate cache on re-acquire** —
   `_shared/acquire/index.ts` store step (lines 153–177). *UX change: none
   visible — prevents refreshed restaurants regressing to cold-start.*
   - Today: `menus` row is deleted → cascades `dishes` → cascades
     `dish_estimates`. Every 30-day freshness refresh throws away the whole
     restaurant's estimates and re-pays Haiku for unchanged dishes.
   - Replace delete-and-recreate with a **diff by identity key**
     `(name_he, section)`:
     1. If a menu row exists, `update` it (`fetched_at: now()`, `scraper`,
        `source_url`, `source`) instead of deleting.
     2. Load existing dishes (`id, name_he, section`). Build the key map.
     3. Incoming dish with a matching key → `update` that row in place
        (description/price/translit may refresh; **id is stable → estimate
        survives**).
     4. Incoming dish with no match → `insert`.
     5. Existing dish not in the incoming set → `delete` (its estimate
        cascades away correctly — the dish is gone from the real menu).
   - Grounding is untouched: we only ever store what the parser extracted.

### Checks

- Browse a seeded menu, select 3 dishes, tap בדיקה: results render **without
  any full-screen spinner** (prefetch hit).
- Select 5 dishes on a *fresh* (uncached) menu quickly and Check immediately:
  cards appear progressively; combined card shows `מתעדכן…` then settles; no
  all-or-nothing spinner.
- Force a re-acquire (`force: true`) of a seeded restaurant, then Check a
  basket: estimates return `cached: true` — the diff kept dish ids stable.
  Verify dish count/names unchanged after the diff (grounding intact).
- Kill one Haiku call (temporarily bad model name on one id): that card shows
  the calm fallback; others render; no full-screen error.
- Worker-pool timing: 12-dish uncached menu estimates measurably faster than
  the wave version (log wall time before/after).
- `flutter analyze` clean; estimator audit (`audit_estimates.sql`) still
  reports `needs_review = 0` after any re-estimates.

---

## Session 13 — Queue: user-first priority, no dead time

**Goal:** a user staring at the pending screen is the most important job in the
system — claim their job first, run jobs concurrently, and remove every
built-in idle gap.

**UX change required: none.** (The pending screen from S11 stays as-is; waits
just get shorter and more predictable.)

### Build

1. **Priority column + claim order** — new migration
   (`supabase/migrations/<ts>_menu_jobs_priority.sql`):
   ```sql
   alter table public.menu_jobs
     add column priority smallint not null default 5;

   -- user-waiting jobs first, then age
   create or replace function claim_menu_jobs(batch int)
     ... order by priority, created_at
     for update skip locked ...;  -- keep the existing claim shape

   drop index if exists menu_jobs_status_idx;
   create index menu_jobs_status_priority_idx
     on public.menu_jobs (status, priority, created_at);

   -- the latestJob lookup (every cache miss + every poll) currently seq-scans
   create index menu_jobs_restaurant_created_idx
     on public.menu_jobs (restaurant_id, created_at desc);
   ```
   - `fetch-menu` `enqueueAndKick`: insert `{ restaurant_id: restaurantId,
     priority: 0 }` (a user is waiting).
   - Freshness cron insert: `priority 9` (background refresh).

2. **Concurrent job processing** — `process-menu-queue/index.ts`
   (lines 75–91):
   - Claim `batch: 2` and run both with `Promise.allSettled`, each getting
     `Math.min(WORKER_BUDGET_MS, remaining - 8_000)`. `claim_menu_jobs` already
     uses `FOR UPDATE SKIP LOCKED`, so concurrency is safe; acquisition is
     network-bound, so two jobs share the instance fine.
   - Keep `MIN_SLOT_MS` / attempts / requeue logic per job unchanged.

3. **Self-rekick when a backlog remains** — end of `processQueue`:
   - After the loop, `select id from menu_jobs where status = 'pending'
     limit 1`; if a row exists, POST the function's own URL with
     `x-queue-secret` inside `EdgeRuntime.waitUntil` (same pattern as
     fetch-menu's `kickWorker`). Generations chain back-to-back; cron becomes
     purely a crash-recovery net. (No infinite-loop risk: a rekick with an
     empty queue exits immediately at the first claim.)

4. **Tighter stuck-job recovery + hygiene** — update
   `supabase/scripts/session9_queue_cron.sql` (idempotent, re-run via
   connector):
   - Stuck threshold: `interval '10 minutes'` → `interval '4 minutes'` (the
     edge runtime hard-kills at ~150s; 4 min covers it with slack).
   - Freshness insert: skip recently-failed places —
     `and not exists (select 1 from menu_jobs f where f.restaurant_id =
     m.restaurant_id and f.status = 'failed' and f.updated_at > now() -
     interval '7 days')` (mirrors fetch-menu's `FAILED_COOLDOWN_DAYS`).
   - Add a purge to the daily job: `delete from public.menu_jobs where status
     in ('done','failed') and updated_at < now() - interval '30 days';`
     (caps table growth; the poll-path index stays fast).

### Checks

- Enqueue a priority-9 batch (simulate freshness), then trigger a live-try
  timeout on a fresh restaurant: the user's priority-0 job is claimed **next**,
  ahead of the batch (verify `menu_jobs` ordering + timestamps).
- Two simultaneous pending users on different restaurants: both jobs run in the
  same worker generation (`done` timestamps within one generation, not
  serialized ~110s apart).
- Load the queue with 4+ jobs: generations chain with no ~60s cron gaps between
  them (compare `updated_at` gaps).
- Kill a worker mid-job (deploy during a run): the job is reset to pending
  within ~4–5 minutes and completes.
- Re-run the cron script twice: idempotent, no duplicate cron jobs
  (`select jobname from cron.job` clean).

---

## Session 14 — Pipeline & scraper depth + Hebrew normalization

*(v3's Session 10, carried over — scope unchanged. This is the organic-coverage
engine: after S10–S13 make the pipeline fast, this makes it deep.)*

**Goal:** the pipeline must reliably capture whatever a user searches —
including the JS-API, PDF and image menus Jina/Firecrawl currently miss — and
emit consistent Hebrew.

**UX change required: none directly** (the app guard from v3 already hides
non-Hebrew descriptions; this session makes the guard unnecessary for new
menus).

**Build:**
- **Scraper depth:** Firecrawl `interact`/actions for JS-gated menus; capture
  the XHR/JSON menu endpoint when items load via an API; harden the PDF path
  (text + garbled-RTL → render-to-image vision) and the image-menu vision path.
- **Discovery:** better own-site + **Hebrew menu-page** resolution (prefer the
  `he` version over `/en/`); broaden menu-subpage detection.
- **Hebrew normalization at parse time:** guarantee `name_he` + `description`
  are always Hebrew (translate/transliterate; keep English in `name_translit`);
  prefer the Hebrew source when a site is bilingual. Grounded — render the real
  dish's text in Hebrew, never invent dishes. DB holds both languages.
- *Context from v3:* the existing catalog was hand-backfilled to consistent
  Hebrew (2026-07-01, dish ids preserved, estimates intact); the app-side guard
  (`menu_screen._showDescription`) already hides non-Hebrew descriptions. This
  session is the pipeline fix so none of that recurs on new menus. Note the
  S12 dish-diff: normalization must run **before** the store step so identity
  keys `(name_he, section)` stay stable across refreshes.

**Checks:**
- On a test set of previously-missed sites (JS / PDF / image), coverage rises
  measurably — record before/after.
- New menus come out fully Hebrew (names + descriptions); both languages stored.
- No-menu sites still return empty / not-covered (no fabrication).
- Inherent limits documented honestly (still-unreadable sites → hand-seed or
  the parked photo-fallback feature).

---

## Session 15 — Quality ops: verification + feedback + observability

*(v3's Session 11, carried over — scope unchanged.)*

**Goal:** watch catalog quality and improve it — verify menus, capture user
corrections, see what the system does and what it costs.

**UX change required: yes, one small addition** — a calm "משהו נראה לא נכון?"
report affordance on the assessment screen (type + optional note → `feedback`
table). Keep it quiet: a text button, not a banner; positives-only framing
stays intact.

**Build:**
- **Verification:** review a menu against `source_url`, flip
  `verified=false → true` (admin via connector/SQL or a tiny protected screen).
  The badge from S8 already renders when true.
- **Feedback:** `feedback` table (`place_id, dish_id, type, note, created_at`),
  RLS anon-insert / no anon-read; the report affordance above.
- **Observability:** internal SQL views — miss rate, top `menu_requests`,
  coverage %, pipeline success/fail by reason, estimate coverage, live-try
  vs queue success split (new: measures S10's win directly), rough spend.

**Checks:**
- Verify a menu → badge shows and persists.
- Feedback writes under correct RLS; visible to you, not publicly readable.
- Metrics reconcile with the DB; miss rate + top requests actionable.

---

## Parked (unchanged v3 decisions — revisit at launch)

- **Abuse & cost guards** — rate limits + daily caps + cost ceilings on the
  public functions. The gate before any public exposure.
- **Accounts & history** — Supabase Auth, saved restaurants, past assessments,
  per-user RLS, notify-when-ready (would replace pending-screen polling with a
  push — worth pairing with launch).
- **Launch & store readiness** — web/PWA vs store, onboarding + disclaimer
  gate, privacy/ToS, crash monitoring, security/RLS review.
- **Later features:** estimator confidence label; dietary filters/tags;
  photo-of-menu fallback; browse-covered-places discovery view; broader
  CI/tests; i18n; allergen data.

## Working agreements

- One session at a time; each ends deployed + live-verified (the v3 S8/S9
  pattern: deploy, hit the real functions, record the observed numbers in this
  file as an **OUTCOME** block under the session).
- Every session's UX changes are listed above **before** building — if a build
  step turns out to need a UX change not listed here, stop and decide it
  deliberately, don't improvise it silently.
- Measure, don't assume: S10 and S12 both include before/after timings; keep
  the numbers in the OUTCOME blocks so v4's thesis stays falsifiable.
