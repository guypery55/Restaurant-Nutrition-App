// Shared menu-acquisition module (build plan v2). One inline pipeline, bounded
// by a hard time budget, reused by the fetch-menu function (live, on a cache
// miss) and by the seed scripts (Session 4). NO agent loop, NO background queue.
//
// Pipeline: resolve own-site URL (skip platforms; one discovery search if needed)
//   → scrape the landing page → discover the menu-category subpages (the full
//     menu usually lives there, not on the homepage) → scrape + grounded-parse
//     the landing page AND every menu page IN PARALLEL → merge/dedupe dishes →
//     store, else log menu_requests. Per page: Jina → looksLikeMenu gate →
//     Firecrawl fallback (incl. a parse-yielded-nothing secondary retry).
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { isPlatformUrl, looksLikeMenu } from "./gates.ts";
import { firecrawlMap, firecrawlScrape, jinaScrape } from "./scrape.ts";
import { type ParsedDish, parseMenuFile, parseMenuText } from "./parse.ts";
import { discoverOwnSite } from "./discover.ts";

// Default ceiling for an inline live fetch. Kept tight on purpose: a user is
// waiting on a spinner, so a miss must degrade within a tolerable window rather
// than stalling the client (a 75s platform-only fetch did exactly that).
// Individual steps are bounded too (discovery 30s, each scrape 25s). Seeded
// restaurants are cache hits and never run this.
//
// Session 9: the budget is now a parameter. fetch-menu passes this default for
// the LIVE try; on a timeout it hands the job to the background worker
// (process-menu-queue), which re-runs acquireMenu with a LONGER budget
// (WORKER_BUDGET_MS) off the request path — so heavy/slow sites that used to
// time out into menu_requests now get acquired instead.
const BUDGET_MS = 55_000;
const IMAGE_EXT = /\.(png|jpe?g|webp|gif)$/;
const ASSET_EXT = /\.(svg|png|jpe?g|webp|gif|pdf|ico|css|js|mp4|woff2?)$/;
const MENU_HINT = /menu|תפריט|%d7%aa%d7%a4%d7%a8%d7%99%d7%98/i; // incl. URL-encoded תפריט
const MAX_MENU_PAGES = 8; // category subpages to crawl (scraped in parallel)

export interface AcquireRestaurant {
  id: string;
  place_id?: string | null;
  name: string;
  address?: string | null;
  website?: string | null;
}

export type AcquireResult =
  | {
    status: "found";
    menu_id: string;
    source_url: string;
    scraper: string;
    dishes: Record<string, unknown>[];
    trace?: unknown;
  }
  | { status: "not_covered"; reason: string; trace?: unknown };

/// Acquire (and store) a menu for one restaurant, bounded by a time budget
/// (defaults to the tight live-try BUDGET_MS; the background worker passes a
/// longer one). On timeout or any miss, logs a menu_requests row and returns
/// "not_covered" with a reason — the caller decides whether "timeout" is worth
/// enqueuing for a background retry vs. a genuine miss.
export async function acquireMenu(
  db: SupabaseClient,
  r: AcquireRestaurant,
  opts: { budgetMs?: number } = {},
): Promise<AcquireResult> {
  const budgetMs = opts.budgetMs ?? BUDGET_MS;
  let timer: number | undefined;
  const timeout = new Promise<AcquireResult>((resolve) => {
    // A timeout is NOT logged as a miss here: fetch-menu's live try enqueues it
    // for a background retry, and the worker logs menu_requests only once the
    // job is finally given up. Genuine misses (no_website / platform_only /
    // no_menu_found) are still logged inside runPipeline where they occur.
    timer = setTimeout(() => {
      resolve({ status: "not_covered", reason: "timeout" });
    }, budgetMs) as unknown as number;
  });
  try {
    return await Promise.race([runPipeline(db, r), timeout]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

async function runPipeline(
  db: SupabaseClient,
  r: AcquireRestaurant,
): Promise<AcquireResult> {
  // 1. Resolve a scrape URL — own site only.
  let url = (r.website ?? "").trim();
  if (!url || isPlatformUrl(url)) {
    const discovered = await discoverOwnSite(r.name, r.address ?? null);
    if (!discovered || isPlatformUrl(discovered)) {
      const reason = url ? "platform_only" : "no_website";
      await logRequest(db, r, reason);
      return { status: "not_covered", reason };
    }
    url = discovered;
  }

  let dishes: ParsedDish[] = [];
  let scraper = "";
  const sourceUrl = url;
  const bare = url.toLowerCase().split("?")[0];
  // deno-lint-ignore no-explicit-any
  const trace: any = { resolved_url: url, candidates: [], pages: [] };

  if (bare.endsWith(".pdf") || IMAGE_EXT.test(bare)) {
    // Direct file menu → vision path.
    dishes = dedupeDishes(await parseMenuFile(url));
    scraper = "vision";
  } else {
    // Scrape the landing page once.
    const landing = await scrapeBest(url);

    // Discover menu-category subpages: links on the page itself + Firecrawl /map.
    const origin = safeOrigin(url);
    const candidates = Array.from(new Set([
      ...extractMenuLinks(landing.text),
      ...(origin ? await firecrawlMap(origin, "menu") : []),
    ])).filter((c) =>
      c !== url &&
      !isPlatformUrl(c) &&
      sameHost(c, url) &&
      MENU_HINT.test(c) &&
      !ASSET_EXT.test(c.toLowerCase().split("?")[0])
    ).slice(0, MAX_MENU_PAGES);
    trace.landing_scraper = landing.scraper;
    trace.landing_len = landing.text.length;
    trace.candidates = candidates;

    // Parse the landing page + every menu page in parallel, then merge.
    const pages = [url, ...candidates];
    const results = await Promise.all(
      pages.map((p) => scrapeAndParse(p, p === url ? landing : null)),
    );

    const merged: ParsedDish[] = [];
    const scrapers = new Set<string>();
    results.forEach((res, i) => {
      trace.pages.push({ url: pages[i], scraper: res.scraper, count: res.dishes.length });
      if (res.dishes.length) {
        merged.push(...res.dishes);
        if (res.scraper) scrapers.add(res.scraper);
      }
    });
    dishes = dedupeDishes(merged);
    scraper = scrapers.size ? [...scrapers].sort().join("+") : "";
  }

  // Miss → log and bail.
  if (dishes.length === 0) {
    await logRequest(db, r, "no_menu_found");
    return { status: "not_covered", reason: "no_menu_found", trace };
  }

  // Store: replace this restaurant's menu + dishes.
  const { data: existing } = await db
    .from("menus")
    .select("id")
    .eq("restaurant_id", r.id)
    .maybeSingle();
  if (existing) await db.from("menus").delete().eq("id", existing.id);

  const { data: menu, error: mErr } = await db
    .from("menus")
    .insert({ restaurant_id: r.id, source: "web", scraper, source_url: sourceUrl })
    .select()
    .single();
  if (mErr || !menu) throw new Error(`Failed to store menu: ${mErr?.message}`);

  const rows = dishes.map((d) => ({
    menu_id: menu.id,
    name_he: d.name_he,
    name_translit: d.name_translit ?? null,
    description: d.description ?? null,
    section: d.section ?? null,
    price: typeof d.price === "number" ? d.price : null,
  }));
  const { data: stored, error: dErr } = await db.from("dishes").insert(rows).select();
  if (dErr) throw new Error(`Failed to store dishes: ${dErr.message}`);

  return {
    status: "found",
    menu_id: menu.id,
    source_url: sourceUrl,
    scraper,
    dishes: stored ?? [],
    trace,
  };
}

/// Scrape one page and grounded-parse it. `pre` lets the caller pass an already
/// scraped landing page to avoid a duplicate fetch. Honors the plan's secondary
/// check: if Jina text parses to 0 dishes, retry the page once via Firecrawl.
async function scrapeAndParse(
  pageUrl: string,
  pre: { text: string; scraper: string } | null,
): Promise<{ scraper: string; dishes: ParsedDish[] }> {
  try {
    const s = pre ?? await scrapeBest(pageUrl);
    let dishes = s.text ? await parseMenuText(s.text) : [];
    let scraper = s.scraper;

    if (dishes.length === 0 && s.scraper === "jina") {
      // Secondary: Jina read it but nothing parsed → try Firecrawl on this page.
      try {
        const fc = await firecrawlScrape(pageUrl);
        if (looksLikeMenu(fc)) {
          const d2 = await parseMenuText(fc);
          if (d2.length) {
            dishes = d2;
            scraper = "firecrawl";
          }
        }
      } catch { /* ignore */ }
    }
    return { scraper, dishes };
  } catch {
    return { scraper: "", dishes: [] };
  }
}

/// Scrape a URL: Jina first; if it fails the menu gate, Firecrawl. Returns text
/// only if it passes looksLikeMenu (empty text otherwise).
async function scrapeBest(url: string): Promise<{ text: string; scraper: string }> {
  let jina = "";
  try {
    jina = await jinaScrape(url);
  } catch {
    jina = "";
  }
  if (looksLikeMenu(jina)) return { text: jina, scraper: "jina" };

  let fc = "";
  try {
    fc = await firecrawlScrape(url);
  } catch {
    fc = "";
  }
  if (looksLikeMenu(fc)) return { text: fc, scraper: "firecrawl" };

  return { text: "", scraper: "" };
}

/// Merge dishes from multiple pages, deduping by normalized name_he and keeping
/// the richest variant (the one carrying a price / description / section).
function dedupeDishes(list: ParsedDish[]): ParsedDish[] {
  const byName = new Map<string, ParsedDish>();
  const score = (x: ParsedDish) =>
    (x.price ? 1 : 0) + (x.description ? 1 : 0) + (x.section ? 1 : 0);
  for (const d of list) {
    const key = d.name_he.replace(/\s+/g, " ").trim();
    const existing = byName.get(key);
    if (!existing || score(d) > score(existing)) byName.set(key, d);
  }
  return [...byName.values()];
}

/// Menu-page links found inside scraped markdown (anchor text or URL hints menu).
function extractMenuLinks(md: string): string[] {
  if (!md) return [];
  const out: string[] = [];
  // Markdown links are [text](url "optional title") — capture only up to the
  // first whitespace/paren so the title doesn't leak into the URL.
  const linkRe = /\[([^\]]*)\]\((https?:\/\/[^\s)]+)/g;
  let m: RegExpExecArray | null;
  while ((m = linkRe.exec(md))) {
    if (MENU_HINT.test(m[1]) || MENU_HINT.test(m[2])) out.push(m[2]);
  }
  const bareRe = /https?:\/\/[^\s)"'\]]+/g;
  while ((m = bareRe.exec(md))) {
    if (MENU_HINT.test(m[0])) out.push(m[0]);
  }
  return Array.from(new Set(out));
}

function brandToken(host: string): string {
  return host.replace(/^www\./, "").split(".")[0];
}

function sameHost(candidate: string, base: string): boolean {
  try {
    const ch = new URL(candidate).hostname;
    return ch.includes(brandToken(new URL(base).hostname));
  } catch {
    return false;
  }
}

function safeOrigin(url: string): string | null {
  try {
    return new URL(url).origin;
  } catch {
    return null;
  }
}

async function logRequest(
  db: SupabaseClient,
  r: AcquireRestaurant,
  reason: string,
): Promise<void> {
  try {
    await db.from("menu_requests").insert({
      place_id: r.place_id ?? null,
      name: r.name,
      reason,
    });
  } catch { /* best-effort logging */ }
}
