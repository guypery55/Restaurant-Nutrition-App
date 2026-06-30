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
2. **Self-healing coverage** — misses fix themselves; the catalog grows on its
   own without hand-seeding every restaurant (with 6 places, a stranger's first
   search almost always misses — that reads as "broken" and kills trust too).

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

- **Session 8 — Estimate trust & accuracy** ✓ *planned (detail below)*
  Self-consistent (4/4/9) + tighter accurate ranges; catalog audit + re-estimate
  fliers; source/freshness + "verified" badge in UI.
- **Session 9 — Background acquisition queue + auto-estimate** *(planning next)*
  Move live fetch off the request path: a miss enqueues and returns instantly
  ("we're getting this menu — check back"); a worker acquires + auto-estimates;
  cron re-fetches stale menus. Fixes the slow-fetch UX **and** lets coverage
  self-heal.
- **Session 10 — Scraper depth + coverage seed push** *(+ display-language fix)*
  Capture the JS-API menus Jina/Firecrawl currently miss; grow the catalog to a
  respectable size via the queue + targeted seeds; track coverage from
  `menu_requests`.
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
- **Session 11 — Verification workflow + user feedback loop**
  A path to flip `verified=false → true`; user-facing "report an issue / looks
  off" on a dish or menu → `feedback` table feeding corrections.
- **Session 12 — Abuse & cost guards** *(pre-exposure hardening)*
  Rate limits + daily caps + cost ceilings on the three functions. Needed before
  ANY public exposure — which is parked, so this lands when launch returns.

### Parked / deferred (revisit when we decide to launch)
- **Accounts & history** — Supabase Auth (anon + optional sign-in), saved
  restaurants, past assessments, per-user RLS, notify-when-ready. Deferred →
  anonymous-only for now.
- **Launch & store readiness** — web/PWA link and/or Android store, onboarding +
  disclaimer gate, privacy/ToS, crash monitoring, security/RLS review. Out of
  near-term scope by decision.

---

## Open questions to resolve as we plan
*(we fill these in together; they drive the detail of each session)*

- **Resolved:** launch surface → parked; accounts → deferred (anonymous-only);
  order → trust then coverage.
- Coverage (S9/S10): target catalog size + which cities/cuisines first? how
  "pending" looks to the user (poll vs check-back)? freshness window?
- Cost guards (S12): per-device limits + acceptable monthly ceiling (decide when
  launch returns).
- Trust (S8/S11): final reconciliation tolerance; how aggressively to tighten
  ranges; where provenance lives (menu vs assessment).

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
