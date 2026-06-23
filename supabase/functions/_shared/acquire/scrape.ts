// Scrapers — free-first. Jina Reader is the primary (free, browser-rendered
// markdown); Firecrawl is the fallback (headless browser + /map page discovery
// + native PDF). Keys live only in function secrets.

const FIRECRAWL_BASE = "https://api.firecrawl.dev/v1";

/// Jina Reader: GET https://r.jina.ai/<full-url> → page as markdown text.
/// Keyless by default; a JINA_API_KEY raises rate limits. Throws on HTTP error.
export async function jinaScrape(url: string): Promise<string> {
  const headers: Record<string, string> = { "X-Return-Format": "markdown" };
  const key = Deno.env.get("JINA_API_KEY");
  if (key) headers["Authorization"] = `Bearer ${key}`;

  const res = await fetch(`https://r.jina.ai/${url}`, { headers });
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
  const res = await fetch(`${FIRECRAWL_BASE}/scrape`, {
    method: "POST",
    headers: firecrawlHeaders(),
    body: JSON.stringify({ url, formats: ["markdown"], onlyMainContent: true }),
  });
  if (!res.ok) throw new Error(`Firecrawl scrape ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data?.data?.markdown ?? "";
}

/// Firecrawl /map — discover a menu page on the domain. Returns candidate URLs
/// (best-effort: empty array on any failure).
export async function firecrawlMap(url: string, search: string): Promise<string[]> {
  try {
    const res = await fetch(`${FIRECRAWL_BASE}/map`, {
      method: "POST",
      headers: firecrawlHeaders(),
      body: JSON.stringify({ url, search }),
    });
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
