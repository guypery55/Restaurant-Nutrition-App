// Acquisition gates: which URLs we may scrape, and whether scraped text looks
// like a real menu (the decision point between Jina and the Firecrawl fallback).

// Domains that are NOT a restaurant's own site. We scrape a restaurant's own
// public site; scraping Wolt/10bis/Instagram is a terms-of-service problem
// regardless of tool, so platform links route to "not covered yet" instead.
export const PLATFORM_BLOCKLIST = [
  "wolt.com",
  "10bis.co.il",
  "mishloha.co.il",
  "tabit.cloud",
  "ontopo",
  "rest.co.il",
  "easy.co.il",
  "facebook.com",
  "instagram.com",
  "linktr.ee",
  "google.com/maps",
  "goo.gl",
  "maps.app.goo.gl",
];

export function isPlatformUrl(url: string): boolean {
  const u = url.toLowerCase();
  return PLATFORM_BLOCKLIST.some((d) => u.includes(d));
}

const PLACEHOLDER_PATTERNS = [
  /enable javascript/i,
  /loading\.\.\./i,
  /please wait/i,
  /just a moment/i,
  /access denied/i,
  /are you a robot/i,
];

const MENU_KEYWORDS = [
  "תפריט", "מנות", "ראשונות", "עיקריות", "קינוחים", "מנה", "ארוחת",
  "menu", "starters", "mains", "desserts", "appetizers", "dishes",
];

const MIN_LENGTH = 400;
const MIN_ITEMS = 5;

/// Decide whether scraped text is a usable menu page. Returns false for empty
/// SPA shells / placeholder / blocked pages (→ fall back to Firecrawl); true
/// only when there is a real menu signal. Thresholds live here for easy tuning.
export function looksLikeMenu(text: string | null | undefined): boolean {
  if (!text) return false;
  const t = text.trim();
  if (t.length < MIN_LENGTH) return false;
  if (PLACEHOLDER_PATTERNS.some((re) => re.test(t))) return false;

  const hasPrice = /₪/.test(t) ||
    /\bNIS\b/.test(t) ||
    /\d+\s*(ש"ח|שח|שקל)/.test(t);
  const hasKeyword = MENU_KEYWORDS.some((k) => t.includes(k));

  const items = new Set(
    t.split(/\n+/).map((s) => s.trim()).filter((s) => s.length > 1 && s.length < 80),
  );
  const enoughItems = items.size >= MIN_ITEMS;

  return hasPrice || hasKeyword || enoughItems;
}
