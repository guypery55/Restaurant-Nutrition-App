# Restaurant Nutrition App — Build Plan v3 (post-MVP → public soft launch)

> **Status: living draft. We plan this together, one session at a time.**
> v2 (`restaurant-nutrition-app-build-plan-v2.md`) remains the record of the
> MVP (Sessions 0–7, shipped). This file covers what takes the app from
> "working MVP" to "something real people can use." Sessions below are sketches
> until we deep-dive each one and fill in its **Build** + **Checks**.

## Where we are (end of v2)

Working loop: search restaurant → menu → basket → AI nutrition estimate
(per-dish + combined, ranges/precise, portions, positives-only highlights) →
graceful "not covered yet" on a miss. Catalog: 6 restaurants seeded (Taizu,
Goocha, M25, McDonald's, Burger Market, Thai House). All keys server-side;
two-layer cache; grounded parsing; estimator is section/portion-aware.

## The goal of v3

Make the app **genuinely good** before worrying about shipping it — earn the
launch rather than rush it. Near-term, two things in priority order:

1. **Trust & accuracy** — estimates and data must feel credible to a stranger.
2. **Self-healing coverage (organic)** — the catalog grows on its own from real
   searches via the live/queue pipeline; **no bulk pre-seeding**. This is a
   deliberate **bet on pipeline quality**: make acquisition good enough that
   misses are rare. Risk accepted (2026-07-01): with only 6 seeded places, early
   coverage rides entirely on that pipeline.

**Parked by decision (2026-06-30):** public launch / app store, and user
accounts. The app stays **anonymous, no-login** for now; launch surface
(web/PWA vs store) is decided later, once trust + coverage are real.

## Known starting facts that shape v3

- All three Edge Functions are public (`verify_jwt = false`) with **no rate
  limiting** — each call costs money (Places / Jina / Firecrawl / Claude). A
  hard blocker before any public exposure.
- **No accounts** — Supabase Auth not wired (passkeys bundle vendored, unused).
- `menus.verified` exists but nothing sets or shows it; all menus are unverified.
- Live-miss fetch is inline + time-capped (responsive, but heavy/slow sites get
  dropped to `menu_requests` rather than acquired) — the real fix is a queue.

---

## Session arc (reshaped 2026-06-30)

Near-term focus: **trust, then coverage.** Launch & accounts are parked (see
below). We still detail each session together before building it.

- **Session 8 — Estimate trust & accuracy** ✓ *BUILT 2026-07-01 (detail below)*
  Self-consistency (4/4/9) with alcohol + near-zero exemptions baked into the
  estimator + restaurant-name context; reusable catalog audit script. **The live
  audit found the estimator was already accurate** (229 real-food estimates,
  median reconciliation error 2.9%, median range ±18.7%, **0 needing review** —
  every flier was alcohol or a near-zero drink), so the accuracy work became a
  forward-looking guardrail for organic estimates, not a catalog rescue, and no
  re-estimation was needed. Trust UI scoped down (user decision): **verified
  badge only**, no source/date line — provenance data stays in the DB for later.
- **Session 9 — Background acquisition queue + auto-estimate** ✓ *BUILT + DEPLOYED + live-verified 2026-07-04 (detail below)*
  Move the **slow** fetch off the request path while keeping a live try: a miss
  first tries to acquire live (~55s); if that's too long it enqueues + returns
  `pending` ("we're working on it") and the app auto-polls; a background worker
  acquires with a longer budget + **auto-estimates**; pg_cron re-kicks the worker
  and re-fetches stale menus. Fixes the slow-fetch UX **and** lets coverage
  self-heal. (Used a `menu_jobs` **table**, not pgmq — see OUTCOME.)
- **Session 10 — Pipeline & scraper depth: the organic coverage engine** *(+ Hebrew text normalization)*
  Coverage is **organic** (no bulk pre-seed): the live/queue pipeline must
  reliably capture whatever a user searches, so this session pushes its depth —
  the JS-API, PDF and image menus Jina/Firecrawl currently miss — and folds in
  the Hebrew text normalization (below).
  **Plus — guarantee consistent Hebrew display TEXT (pipeline-level):** the
  grounded parser stores "the original text" into `name_he` AND `description`, so
  an English / bilingual source (or the multi-page merge blending an English
  landing page with a Hebrew subpage) yields English or mixed text — the app then
  shows a half-Hebrew/half-English menu (first seen in Taizu). Fix it at the parse
  step: (a) **normalize** so `name_he` AND `description` are *always* Hebrew
  (translate/transliterate; keep the English in `name_translit`) — consistency by
  construction; (b) **prefer the Hebrew source** when a site is bilingual (favor
  the `he` version over `/en/`) so we get *authentic* text. Grounded: we render an
  existing dish's name/description in Hebrew, never invent dishes. The DB should
  hold BOTH languages per dish (`name_he` Hebrew + `name_translit` English); the
  app displays Hebrew.
  > **Existing catalog backfilled by hand (2026-07-01, no API cost):** the whole
  > catalog is now consistent Hebrew — **0 English names, 0 English descriptions**
  > (verified). Done: names → Hebrew (Goocha 49, Taizu 8; authentic from Hebrew
  > menus where available, else faithful renderings); **`name_translit` filled for
  > all** (Thai House's 67 English/Latin names added) so the DB holds both
  > languages everywhere; **descriptions → Hebrew** (Taizu 27 authentic from its
  > Hebrew menu; Goocha 44 + McDonald's 29 translated; M25/McDonald's redundant
  > name-glosses nulled since those real menus carry no item descriptions). Dish
  > ids preserved → estimates intact, nothing re-run. Tried Firecrawl on Goocha's
  > Hebrew PDF — RTL text extraction came back garbled, so authentic full-Hebrew
  > from that PDF isn't viable; our renderings stand until the pipeline can prefer
  > a clean Hebrew source. Remaining work for S10 is the *pipeline* fix so none of
  > this recurs on new menus.
  > **App guard already shipped:** the menu shows a description ONLY if it
  > contains Hebrew (`menu_screen._showDescription`), so any not-yet-normalized
  > English description (e.g. a fresh live fetch before S10) is hidden rather than
  > shown under a Hebrew menu.
- **Session 11 — Quality ops: verification + feedback + observability**
  Flip `verified=false → true`; user "report an issue / looks off" → `feedback`
  table feeding corrections; plus an internal **metrics view** (miss rate, top
  `menu_requests`, coverage %, pipeline success/fail, spend) that tells us what to
  improve and what it costs.

> Near-term arc ends at Session 11. Everything below is parked until we choose to
> launch.

### Parked / deferred (revisit when we decide to launch)
- **Abuse & cost guards** — per-device/IP rate limits + daily caps + cost
  ceilings on the three open functions (`verify_jwt=false`). Fully parked
  2026-07-01: no users yet, so nothing to abuse; this is the gate to add right
  before any public exposure. (A global spend-cap safety net can be dropped in
  anytime if test usage grows.)
- **Accounts & history** — Supabase Auth (anon + optional sign-in), saved
  restaurants, past assessments, per-user RLS, notify-when-ready. Deferred →
  anonymous-only for now.
- **Launch & store readiness** — web/PWA link and/or Android store, onboarding +
  disclaimer gate, privacy/ToS, crash monitoring, security/RLS review. Out of
  near-term scope by decision.
- **Later features (considered, consciously deferred 2026-07-01):** estimator
  confidence label (high/med/low); dietary filters/tags (vegan / gluten-free /
  high-protein); photo-of-menu fallback (user uploads a menu photo → grounded
  vision parse — the true last resort for coverage).
- **Also considered, out of near-term scope:** discovery UX (browse / nearby /
  popular — note: with organic coverage users can't easily tell what's covered,
  so a "browse covered places" view may be worth revisiting); broader automated
  tests/CI; English UI / i18n; allergen data. Logged here so they're not silently
  missed; none block the trust+coverage work.

---

## Open questions to resolve as we plan
*(we fill these in together; they drive the detail of each session)*

- **Resolved (2026-06-30 / 07-01):** launch & store → parked; accounts → parked
  (anonymous-only); cost/abuse guards → parked (no users yet); order → trust then
  coverage; coverage strategy → **organic** (no bulk seed — the pipeline is the
  engine); observability → **in** (S11); confidence label / dietary filters /
  photo fallback → parked as later features.
- **Decide in-session (S9):** pending-menu UX (auto-appear via poll/Realtime vs
  "check back") — guided by "misses should be rare because the pipeline is good";
  freshness window length.
- **Decide in-session (S8/S11):** reconciliation tolerance; how aggressively to
  tighten ranges; where provenance lives (menu vs assessment); verification
  surface (connector/SQL vs a tiny protected screen).

---

## Detailed sessions
*(filled in as we deep-dive each one)*

### Session 8 — Estimate trust & accuracy

**Goal:** estimates a stranger can trust — internally coherent, tighter (not
artificially), and visibly grounded in the real menu. Comfort comes from
*accurate + tighter ranges + visible provenance*, not a confidence label.

**Decisions locked (2026-06-30):**
- Push accuracy via **self-consistency + tighten** (chosen over light-fix / heavy
  two-pass). No extra per-dish cost.
- A wide range around a wrong number is worse than an honest wide one → tighten
  ONLY together with accuracy; calibrate, don't just shrink.
- Explicit confidence label (high/med/low) is **deferred** — revisit only if
  accuracy + provenance don't feel like enough.

**Build:**

1. **Estimator upgrade** (`_shared/estimate`):
   - Enforce **macro/calorie self-consistency**: the returned macros must
     reconcile with calories via `4·protein + 4·carbs + 9·fat` within a
     tolerance; the model checks itself before returning.
   - Feed **more context** to anchor the estimate: restaurant name + cuisine/type
     (and price tier if useful), on top of the section we already pass.
   - Instruct a **realistic, tighter range** (target roughly ±15–20% around the
     point estimate, not a 2× CYA spread) while staying honest.
   - Keep the section/portion rules from the Session-7 fix (topping vs full dish).
   - Caveat to handle: alcohol is ~7 cal/g and fiber/sugar-alcohols bend 4/4/9 —
     loosen/skip the strict check for drinks/alcohol so it doesn't false-flag.

2. **Catalog estimate audit** (script or SQL via the connector):
   - Reconciliation error per estimate:
     `|cal_mid − (4·prot_mid + 4·carb_mid + 9·fat_mid)| / cal_mid` → flag > ~20%.
   - Also flag: absurd range width (width/mid over a threshold), impossible
     macros vs calories, zero/negative values.
   - **Re-estimate** flagged dishes with the upgraded estimator; report
     before/after (count inconsistent, count fixed, median range width before vs
     after). Persistent fliers → flag for human review (hands off to Session 9).

3. **Provenance & trust in the UI:**
   - On the menu and/or assessment screen show: "מבוסס על התפריט מ-`<domain>`,
     עודכן `<date>`" and a **verified** badge when `menus.verified = true`.
   - A calm, reachable "איך אנחנו מעריכים" (how we estimate) one-liner —
     transparent, not nagging.

**Checks:**
- Every estimate reconciles within tolerance (alcohol/drinks excepted); audit
  reports 0 remaining inconsistent (or explicitly flagged).
- Median range width measurably reduced vs before (record the numbers).
- Spot-check the known-bad cases (e.g. the onion topping) stay correct; no new
  absurd values introduced by tightening.
- UI shows source + freshness + verified badge; tone stays neutral/non-shaming.
- Re-estimation is idempotent + cached (numbers stable on re-check).

**Still open for Session 8 (decide during build):** exact reconciliation
tolerance; how aggressively to tighten (calibrate against the audit); whether
provenance lives on the menu screen, the assessment screen, or both.

**OUTCOME (built 2026-07-01):**

*What the live audit showed (251 estimates, before touching anything):* median
reconciliation error **3.1%**, median calorie range width **37.6% (≈ ±19%,
already at the ±15-20% target)**. All 13 fliers over tolerance were **alcohol**
(beer/cider — ethanol ~7 cal/g breaks 4/4/9) or **near-zero drinks** (diet
sodas / water — a 2-vs-3 kcal gap reads as huge % noise). In the 10-20% band,
real food maxed at 18%. **Zero genuinely-wrong real-food estimates.** So the
estimator was already accurate; the session re-weighted from "rescue the catalog"
to "guardrail future organic estimates + ship the trust surface the user wants."

*Decisions locked:*
- **Reconciliation tolerance = 20% relative**, with two exemptions the data
  demanded: **alcohol tags skipped entirely**, and **items < 30 kcal excluded**
  (identity meaningless at that scale). Every real-food estimate passes; every
  false positive is excluded.
- **No forced tightening** — already at ±19% median; shrinking further would
  manufacture false precision. Calibrate, don't shrink (the plan's own principle).
- **Estimator scope = forward-looking guardrail only** — upgrade the prompt so
  new/organic estimates stay clean (S9/S10 auto-estimate); **no mass
  re-estimate** (nothing real to fix; re-running alcohol wouldn't/shouldn't
  reconcile anyway).
- **Trust UI scoped down (user):** **verified badge only** on the menu screen —
  no "based on `<domain>`, updated `<date>`" line, no "how we estimate" text.
  Provenance (`source_url`, `fetched_at`, `verified`) stays in the DB and is now
  threaded to the client, ready to surface in a later session.

*Built:*
- `_shared/estimate/index.ts` — prompt now (a) self-checks 4·P+4·C+9·F↔calories
  within ~20% before returning, **exempting alcohol & <30 kcal**; (b) receives
  the **restaurant name** (embedded via dishes→menus→restaurants) as anchoring
  context; (c) asks for an honest-but-tight ±15-20% range. Kept the S7
  section/portion (topping vs full dish) rules. No extra per-dish call — all
  prompt-level, so cost is unchanged.
- `supabase/scripts/audit_estimates.sql` — reusable, read-only audit with the
  classification-aware verdict (alcohol / near_zero / real_food; only real_food
  out of tolerance = `needs_review`). Re-run confirms **needs_review = 0**.
  Reused by S11 metrics.
- `fetch-menu` → `MenuResult` → `menu_screen`: `verified` (+ `fetched_at`) now
  flow to the client; a calm green "תפריט מאומת" badge renders when
  `verified = true`. Invisible today (0 verified menus); S11's verification flow
  flips it on.

*Checks met:* audit reports 0 real-food inconsistencies (alcohol/near-zero
explicitly exempt); ranges left at the honest ±19% median (not artificially
shrunk); known-good topping/portion behavior preserved by keeping the S7 rules;
badge wired end-to-end. **Deployed** `estimate-dishes` + `fetch-menu` and ran a
live spot-check: cleared + re-estimated the Heineken beer through the new prompt
— it returned ~50 kcal tagged `alcoholic` with reasoning about ethanol calories
and did NOT force macro reconciliation (the exemption works); catalog re-audited
`needs_review = 0`. Committed on branch `session-8-estimate-trust`. *(Known nit,
out of scope: alcohol calories skew low — a 330 ml Heineken is ~140 kcal; not
chased, alcohol is exempt from the accuracy target.)*

---

### Session 9 — Background acquisition queue + auto-estimate

**Goal:** take live acquisition **off the request path** so a miss never blocks
the user, and so organic coverage can grow reliably (no inline timeout dropping
heavy/slow sites). This is the structural fix behind the "make misses rare" bet.

**Build:**
- A queue (Supabase **pgmq**) + a **worker** (pg_cron-invoked Edge Function, or
  pg_cron calling a function) that runs `acquireMenu` for queued restaurants.
- `fetch-menu` on a cache miss: **enqueue** the restaurant and return `pending`
  immediately — no inline scrape, no waiting.
- Worker per job: `acquireMenu` → store menu + dishes → **auto-run
  `estimate-dishes`** for the new dishes (a covered menu is instantly usable) →
  Hebrew-normalize (S10).
- De-dupe / state: never enqueue a place already pending; track job status; cap
  retries; record failures.
- **Freshness:** cron re-enqueues menus older than the freshness window.

**Decide in-session:** the pending UX (auto-appear via poll/Realtime vs "check
back later") — optimize the common *cached* path first; misses should be rare.

**Checks:**
- A miss returns instantly as `pending` (no long wait); the worker fills it
  within ~minutes; dishes + estimates appear on the next view.
- No request-path stalls; the inline time budget no longer gates the user.
- Stale menus get re-acquired by cron; re-enqueue is idempotent; concurrent
  requests for one place don't double-process.
- No-menu results still log `menu_requests` with a reason; **zero fabrication**.

**OUTCOME (built + deployed + live-verified 2026-07-04):**

*Shape the user chose (this reshaped the plan's "enqueue immediately"):* keep the
**live try**, then fall back to the queue. fetch-menu still attempts a live
acquire while the user waits (~55s budget — the proven inline value, ≈ the "60s"
the user picked); only if that budget is exceeded does it hand off to the
background queue and return `pending` → *"אנחנו אוספים את התפריט הזה… כמה דקות
ונחזור אליך."* The pending screen **auto-polls** every 15s (×8, ~2 min) so the
menu appears on its own, then offers a manual refresh (user chose auto-poll over
"check back").

*Deliberate deviation from the plan text:* it named **pgmq**; we used a plain
**`menu_jobs` table** instead. The plan's own checks (de-dupe, status tracking,
retry caps, failure records) are trivial with a table + a **partial unique index**
(`where status in ('pending','processing')` → idempotent enqueue, no
double-process) and awkward with pgmq (no native dedupe).

*Built:*
- **DB** (migration `20260704120000_menu_jobs_queue`): enabled `pg_cron` +
  `pg_net`; `public.menu_jobs` (status pending/processing/done/failed, attempts,
  reason, last_error) + partial-unique active index + `claim_menu_jobs(batch)`
  — an atomic `FOR UPDATE SKIP LOCKED` claim so two worker invocations never grab
  the same job. RLS on, no anon policy (client polls fetch-menu, never reads the
  table).
- **Worker** `process-menu-queue` (new Edge Function, `verify_jwt=false`, guarded
  by the shared `QUEUE_WORKER_SECRET` in `x-queue-secret`): claims jobs → runs
  `acquireMenu` with a **longer 110s budget** (the whole point — heavy sites that
  time out the live try get acquired here) → **auto-runs `estimateDishes`** on the
  new dishes so a covered menu is instantly usable → marks done/failed. Timeouts
  retry (cap 3); genuine misses fail immediately (already logged to
  menu_requests). Responds 202 + drains in `EdgeRuntime.waitUntil`; a `{wait:true}`
  mode drains synchronously (used for testing).
- **fetch-menu** (hybrid): cache hit → serve; else if an active job exists →
  `pending`; else if a **recent failed** job (7-day cooldown) → `not_covered`
  without re-spending on a known-dead site; else **live try** → found, or on
  `timeout` enqueue + fire-and-forget kick the worker + `pending`, or a genuine
  miss → `not_covered`. `acquireMenu` now takes a `budgetMs`; its timeout no
  longer self-logs a miss (the caller decides queue-vs-give-up).
- **Cron** (`session9_queue_cron.sql`, run via connector): `menu-queue-tick`
  every minute — reset jobs stuck `processing` >10 min, then `net.http_post` the
  worker (reading the secret from **Vault**) only when pending work exists;
  `menu-queue-freshness` daily 03:00 UTC — re-enqueue menus older than 30 days.
- **Auth** with no new key-management pain: one `QUEUE_WORKER_SECRET` set via CLI
  (project-wide → both fetch-menu's kick and the worker see it) + stored in Vault
  (→ cron reads it). No service-role key ever handled.
- **Client:** `MenuResult.pending` state; `menu_screen` refactored from a
  one-shot FutureBuilder to imperative load + a `_Pending` widget that auto-polls.

*Checks met — live-verified against the deployed functions:*
- Worker auth: missing/wrong secret → **401**; empty queue → no-op.
- **Cron tick fires**: within a minute of enqueue it kicked a worker that claimed
  the job (observed status → `processing`).
- **Full success path**: a throwaway restaurant pointed at a real menu → acquired
  **57 dishes + auto-estimated all 57 → `done`** in ~105s (via the cron kick).
- **Headline live-try loop**: fetch-menu on a heavy site ran ~58s live, timed
  out, enqueued + kicked, returned `pending`; the worker it kicked then filled the
  menu (53 dishes + estimates) — no cron needed.
- Genuine miss (Instagram-only place) → `not_covered` + `menu_requests` logged +
  **0 jobs enqueued** (a real miss never clogs the queue).
- Active job → `pending` in ~3s (no live try); recent-failed → `not_covered` in
  ~3s (no re-spend). `flutter analyze` clean.

*Known accepted cost:* on a live-try **timeout**, the site is scraped twice (the
wasted ~55s live attempt, then the worker re-acquires from scratch — no resume).
That's the price of the "try live first" UX the user wanted; acceptable because
misses are rare and cost guards are parked pre-launch.

*Still open (not blocking):* the live-try wastes work on a timeout (above); a
per-place concurrency edge (two simultaneous first-time visitors both run a live
try before either enqueues) — harmless, just double spend on that rare race.

---

### Session 10 — Pipeline & scraper depth (organic coverage engine) + Hebrew normalization

**Goal:** because coverage is **organic**, the pipeline must reliably capture
whatever a user searches — including the JS-API, PDF and image menus it currently
misses — and emit consistent Hebrew. (See the arc entry above for the full Hebrew
normalization spec + the already-done hand-backfill + shipped app guard.)

**Build:**
- **Scraper depth:** add Firecrawl `interact`/actions to render JS-gated menus;
  capture the **XHR/JSON menu endpoint** when items load via an API; harden the
  **PDF** path (text + the garbled-RTL case → render-to-image vision) and the
  **image-menu vision** path.
- **Discovery:** better own-site + **Hebrew menu-page** resolution (prefer the
  `he` version over `/en/`); broaden menu-subpage detection.
- **Hebrew text normalization:** parse-time guarantee `name_he` + `description`
  are Hebrew, English kept in `name_translit`; prefer the Hebrew source.
- Keep grounding throughout — never invent.

**Checks:**
- On a test set of previously-missed sites (JS / PDF / image), coverage rises
  measurably — record before/after.
- New menus come out **fully Hebrew** (names + descriptions); both languages
  stored per dish.
- No-menu sites still return empty / not-covered (no fabrication).
- Inherent limits documented honestly (sites still unreadable → hand-seed or
  later photo fallback).

---

### Session 11 — Quality ops: verification + feedback + observability

**Goal:** watch the catalog's quality and improve it — verify menus, capture user
corrections, and see how the system performs (which also informs coverage and the
future cost guards).

**Build:**
- **Verification:** review a menu against its `source_url` and flip
  `verified=false → true` (admin via the Supabase connector/SQL, or a tiny
  protected screen — it's just you for now). Surface the verified badge (built in
  S8).
- **Feedback:** user "report an issue / looks off" on a dish or menu → a
  `feedback` table (`place_id, dish_id, type, note, created_at`) with RLS (anon
  insert, no anon read); no anti-abuse needed pre-launch.
- **Observability/metrics:** internal SQL views (or a tiny page) — miss rate, top
  `menu_requests` (what to cover next), coverage %, pipeline success/fail by
  reason, estimate coverage, and a rough **spend** view from function logs/usage.

**Checks:**
- Verify a menu → the badge shows and persists.
- Feedback writes a row under correct RLS; visible to you, not publicly readable.
- Metrics reconcile with the DB (counts match); miss rate + top requests are
  actionable (drive what S10 improves next).
