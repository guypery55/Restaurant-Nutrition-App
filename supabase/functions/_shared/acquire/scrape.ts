// Scrapers — free-first. Jina Reader is the primary (free, browser-rendered
// markdown); Firecrawl is the fallback (headless browser + /map page discovery
// + native PDF). Keys live only in function secrets.

const FIRECRAWL_BASE = "https://api.firecrawl.dev/v1";

// Per-call timeouts. The overall acquire budget is the ceiling, but no single
// external call may hang toward it — a slow scraper/search must fail fast so a
// miss returns a graceful "not covered" quickly instead of stalling the client.
const JINA_TIMEOUT_MS = 25_000;
const FIRECRAWL_TIMEOUT_MS = 25_000;
const FIRECRAWL_MAP_TIMEOUT_MS = 15_000;

/// fetch() with a hard timeout via AbortController. Throws (AbortError) if the
/// request outlasts `ms`; callers treat that like any other fetch failure.
export async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  ms: number,
): Promise<Response> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(t);
  }
}

/// Jina Reader: GET https://r.jina.ai/<full-url> → page as markdown text.
/// Keyless by default; a JINA_API_KEY raises rate limits. Throws on HTTP error.
export async function jinaScrape(url: string): Promise<string> {
  const headers: Record<string, string> = { "X-Return-Format": "markdown" };
  const key = Deno.env.get("JINA_API_KEY");
  if (key) headers["Authorization"] = `Bearer ${key}`;

  const res = await fetchWithTimeout(`https://r.jina.ai/${url}`, { headers }, JINA_TIMEOUT_MS);
  if (!res.ok) throw new Error(`Jina ${res.status}`);
  return await res.text();
}

function firecrawlHeaders(): Record<string, string> {
  const key = Deno.env.get("FIRECRAWL_API_KEY");
  if (!key) throw new Error("FIRECRAWL_API_KEY is not configured.");
  return { "Content-Type": "application/json", "Authorization": `Bearer ${key}` };
}

/// Firecrawl /scrape — headless-browser render → markdown. Throws on HTTP error.
export async function firecrawlScrape(url: string): Promise<string> {
  const res = await fetchWithTimeout(`${FIRECRAWL_BASE}/scrape`, {
    method: "POST",
    headers: firecrawlHeaders(),
    body: JSON.stringify({ url, formats: ["markdown"], onlyMainContent: true }),
  }, FIRECRAWL_TIMEOUT_MS);
  if (!res.ok) throw new Error(`Firecrawl scrape ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data?.data?.markdown ?? "";
}

/// Firecrawl /map — discover a menu page on the domain. Returns candidate URLs
/// (best-effort: empty array on any failure).
export async function firecrawlMap(url: string, search: string): Promise<string[]> {
  try {
    const res = await fetchWithTimeout(`${FIRECRAWL_BASE}/map`, {
      method: "POST",
      headers: firecrawlHeaders(),
      body: JSON.stringify({ url, search }),
    }, FIRECRAWL_MAP_TIMEOUT_MS);
    if (!res.ok) return [];
    const data = await res.json();
    const links = data?.links ?? [];
    // v1 returns either string URLs or { url, title, description } objects.
    return (links as unknown[])
      .map((l) => (typeof l === "string" ? l : (l as { url?: string }).url))
      .filter((u): u is string => Boolean(u));
  } catch {
    return [];
  }
}
