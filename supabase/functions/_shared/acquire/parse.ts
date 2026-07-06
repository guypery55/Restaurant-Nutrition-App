// Grounded parser — one Claude call that turns scraped content (markdown, or a
// PDF/image via vision) into structured dishes, or an empty list. No web tools,
// no thinking: this is mechanical extraction and must be fast and cheap.

import { fetchWithTimeout } from "./scrape.ts";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
// Haiku (overridable via PARSE_MODEL): grounded JSON extraction is exactly its
// use case, and output-token speed dominates parse latency. Discovery keeps its
// own model (MENU_MODEL, Sonnet) — the two were split in Session 10.
const PARSE_MODEL = Deno.env.get("PARSE_MODEL") ?? "claude-haiku-4-5";
// Anti-hang bound, not pacing: without it a stuck Anthropic call silently eats
// the caller's whole acquisition budget. Generous enough for a legitimately
// large menu's JSON (thousands of output tokens).
const PARSE_TIMEOUT_MS = 40_000;
// Real menus never need more input than this; the tail of an oversized scrape
// is nav/footer/blog noise that costs input tokens and seconds.
const MAX_PARSE_CHARS = 80_000;

const GROUNDED_PROMPT =
  `You are given the raw content of a web page or image that may contain a
restaurant menu. Extract ONLY dishes that actually appear in the provided
content. Do NOT add, infer, or invent any dish from general knowledge. If the
content contains no menu, return an empty list.

For each dish return: name_he (original text, usually Hebrew), name_translit
(Latin transliteration), description (if present), section (if present), price
(number only, if present).

SPLIT PRICE-GROUPED OPTION LISTS. Menus often put several separate, individually
orderable items on ONE line that share a single price — typically toppings,
add-ons, soft drinks, juices, sides, or beers, e.g. "Fried egg / Portobello /
Grilled pepper — 9" or "Pepsi / Cola / Sprite — 12". When a line lists multiple
items separated by "/" (or "," / "•") where EACH segment is a complete,
standalone item you could order on its own, return EACH option as its OWN
dish — every one carrying that shared price, the same section, and (if any) the
same description.

Do NOT split when the separator only joins variants or adjectives of a SINGLE
dish rather than distinct items: "Vegan / Vegetarian burger" is ONE dish (the
"/" picks a diet of the same burger), and a compound name like "Mix potato &
sweet-potato fries" or "Peanut butter & bamba" is ONE dish. Rule of thumb: if a
segment, standing alone, names a thing you could order by itself, split it out;
if a segment is just a modifier of a shared noun, keep the line as one dish.

Respond with ONLY a JSON object: { "dishes": [ { "name_he": "...",
"name_translit": "...", "description": "...", "section": "...", "price": 0 } ] }.
No prose, no markdown.`;

export interface ParsedDish {
  name_he: string;
  name_translit?: string | null;
  description?: string | null;
  section?: string | null;
  price?: number | null;
}

/// Parse scraped markdown/text into dishes.
export function parseMenuText(content: string): Promise<ParsedDish[]> {
  return callParse([{
    type: "text",
    text: `Raw page content to parse:\n\n${content.slice(0, MAX_PARSE_CHARS)}`,
  }]);
}

/// Parse a PDF or image menu via Claude vision (Claude fetches the URL itself).
export function parseMenuFile(url: string): Promise<ParsedDish[]> {
  const isPdf = url.toLowerCase().split("?")[0].endsWith(".pdf");
  const fileBlock = isPdf
    ? { type: "document", source: { type: "url", url } }
    : { type: "image", source: { type: "url", url } };
  return callParse([
    fileBlock,
    { type: "text", text: "Parse the menu in this file following the rules." },
  ]);
}

async function callParse(userContent: unknown[]): Promise<ParsedDish[]> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not configured.");

  const res = await fetchWithTimeout(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: PARSE_MODEL,
      max_tokens: 6000,
      thinking: { type: "disabled" },
      system: GROUNDED_PROMPT,
      messages: [{ role: "user", content: userContent }],
    }),
  }, PARSE_TIMEOUT_MS);
  if (!res.ok) {
    throw new Error(`Parse request failed (${res.status}): ${await res.text()}`);
  }
  const data = await res.json();
  const text = (data.content as Array<Record<string, unknown>> | undefined)
    ?.filter((b) => b.type === "text")
    .map((b) => b.text as string)
    .join("")
    .trim() ?? "";
  return extractDishes(text);
}

/// Tolerant JSON extraction — strips stray fences, validates the shape, drops
/// nameless rows. Returns [] on anything malformed (never throws on garbage).
export function extractDishes(text: string): ParsedDish[] {
  let cleaned = text.trim();
  const fence = cleaned.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) cleaned = fence[1].trim();
  if (!cleaned.startsWith("{")) {
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start === -1 || end === -1) return [];
    cleaned = cleaned.slice(start, end + 1);
  }
  try {
    const obj = JSON.parse(cleaned);
    if (!obj || !Array.isArray(obj.dishes)) return [];
    return (obj.dishes as ParsedDish[])
      .filter((d) =>
        d && typeof d.name_he === "string" && d.name_he.trim().length > 0
      )
      .map((d) => ({
        name_he: d.name_he.trim(),
        name_translit: d.name_translit ?? null,
        description: d.description ?? null,
        section: d.section ?? null,
        price: typeof d.price === "number" ? d.price : null,
      }));
  } catch {
    return [];
  }
}
