// Shared nutrition-estimation module (build plan v2, Session 6). One Haiku call
// per dish that turns a dish name + description into nutrition RANGES, cached
// one-per-dish in `dish_estimates` for consistency (principle #3). Reused by the
// estimate-dishes function (live, on a basket check) and by the Session 4 seed
// batch. Estimation is cheap + high-volume → Haiku, not Sonnet.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ESTIMATE_MODEL = Deno.env.get("ESTIMATE_MODEL") ?? "claude-haiku-4-5";
const MAX_CONCURRENT = 5; // be gentle on rate limits during the seed batch

const ESTIMATOR_PROMPT =
  `You are estimating the nutrition of a SINGLE restaurant item for a
general-interest app. This is NOT for medical use.

You are given the item's name, its menu SECTION, and (if any) a description. Use
the section as context for BOTH what the item is and how large a portion to
assume:
- A standalone dish (starter, main, salad, soup, dessert, etc.) → a typical
  single restaurant serving.
- A TOPPING / ADD-ON / EXTRA (e.g. a section like "תוספות", "תוספות להמבורגר",
  "add-ons", "toppings", "extras") → ONLY the small portion actually added on top
  of another dish (often ~15-40g, e.g. a spoonful of an ingredient), NOT a full
  standalone serving.
- A SIDE or a DRINK → a typical side / single drink portion.

Interpret ambiguous preparations by this context and plain meaning. For example,
"בצל מטוגן" (fried onion) as a burger topping is a small amount of sautéed /
caramelized onion, NOT battered deep-fried onion rings — assume a battered /
breaded / "rings" / "crispy" form only if the name explicitly says so.

First decompose the item into its likely components and portion in one short
reasoning sentence, then give the ranges (low to high) to express uncertainty.
Use realistic Israeli / Middle-Eastern portion sizes.

Return ONLY this JSON:
{ "calories_low":0,"calories_high":0,"protein_low":0,"protein_high":0,
  "carbs_low":0,"carbs_high":0,"sugar_low":0,"sugar_high":0,"fat_low":0,"fat_high":0,
  "tags":["high-protein","fried"], "reasoning":"one short sentence" }
No prose, no markdown.`;

export interface DishEstimate {
  dish_id: string;
  calories_low: number;
  calories_high: number;
  protein_low: number;
  protein_high: number;
  carbs_low: number;
  carbs_high: number;
  sugar_low: number;
  sugar_high: number;
  fat_low: number;
  fat_high: number;
  tags: string[];
  reasoning: string;
  model: string;
  cached: boolean;
}

interface DishRow {
  id: string;
  name_he: string;
  name_translit: string | null;
  description: string | null;
  section: string | null;
}

/// Estimate nutrition for a set of dish ids. Cache hit → reuse the stored row
/// (numbers never wobble); miss → call Haiku, store, return. Order of the result
/// follows `dishIds`; ids that don't exist are skipped.
export async function estimateDishes(
  db: SupabaseClient,
  dishIds: string[],
): Promise<DishEstimate[]> {
  const ids = [...new Set(dishIds.filter((x) => typeof x === "string" && x))];
  if (ids.length === 0) return [];

  // Fetch dish text + any already-cached estimates in two reads.
  const [{ data: dishes }, { data: cached }] = await Promise.all([
    db.from("dishes").select("id, name_he, name_translit, description, section").in("id", ids),
    db.from("dish_estimates").select("*").in("dish_id", ids),
  ]);

  const dishById = new Map<string, DishRow>((dishes ?? []).map((d) => [d.id, d as DishRow]));
  const cachedById = new Map<string, Record<string, unknown>>(
    (cached ?? []).map((c) => [c.dish_id as string, c]),
  );

  const misses = ids.filter((id) => dishById.has(id) && !cachedById.has(id));

  // Estimate the misses with a small concurrency cap, then store them.
  const fresh = new Map<string, DishEstimate>();
  for (let i = 0; i < misses.length; i += MAX_CONCURRENT) {
    const batch = misses.slice(i, i + MAX_CONCURRENT);
    const results = await Promise.all(
      batch.map(async (id) => {
        const est = await estimateOne(dishById.get(id)!);
        return est ? { id, est } : null;
      }),
    );
    for (const r of results) {
      if (!r) continue;
      const row = { dish_id: r.id, ...r.est, model: ESTIMATE_MODEL };
      const { error } = await db.from("dish_estimates").insert(row);
      if (error && !error.message.includes("duplicate")) {
        console.error(`store estimate failed for ${r.id}:`, error.message);
      }
      fresh.set(r.id, toEstimate(r.id, row, false));
    }
  }

  // Assemble in request order: cached first-class, then freshly computed.
  const out: DishEstimate[] = [];
  for (const id of ids) {
    if (cachedById.has(id)) out.push(toEstimate(id, cachedById.get(id)!, true));
    else if (fresh.has(id)) out.push(fresh.get(id)!);
  }
  return out;
}

function toEstimate(
  dishId: string,
  row: Record<string, unknown>,
  cached: boolean,
): DishEstimate {
  const num = (v: unknown) => (typeof v === "number" ? v : Number(v) || 0);
  return {
    dish_id: dishId,
    calories_low: num(row.calories_low),
    calories_high: num(row.calories_high),
    protein_low: num(row.protein_low),
    protein_high: num(row.protein_high),
    carbs_low: num(row.carbs_low),
    carbs_high: num(row.carbs_high),
    sugar_low: num(row.sugar_low),
    sugar_high: num(row.sugar_high),
    fat_low: num(row.fat_low),
    fat_high: num(row.fat_high),
    tags: Array.isArray(row.tags) ? (row.tags as string[]) : [],
    reasoning: typeof row.reasoning === "string" ? row.reasoning : "",
    model: typeof row.model === "string" ? row.model : ESTIMATE_MODEL,
    cached,
  };
}

type EstimateFields = Omit<DishEstimate, "dish_id" | "model" | "cached">;

/// One Haiku call for one dish. Returns null on any error / malformed output
/// (the caller skips it rather than storing garbage).
async function estimateOne(dish: DishRow): Promise<EstimateFields | null> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not configured.");

  const name = [dish.name_translit, dish.name_he].filter(Boolean).join(" / ");
  const userText = `Item: ${name}` +
    (dish.section ? `\nSection: ${dish.section}` : "") +
    (dish.description ? `\nDescription: ${dish.description}` : "");

  try {
    const res = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: ESTIMATE_MODEL,
        max_tokens: 1024,
        system: ESTIMATOR_PROMPT,
        messages: [{ role: "user", content: userText }],
      }),
    });
    if (!res.ok) {
      console.error(`estimate request failed (${res.status}): ${await res.text()}`);
      return null;
    }
    const data = await res.json();
    const text = (data.content as Array<Record<string, unknown>> | undefined)
      ?.filter((b) => b.type === "text")
      .map((b) => b.text as string)
      .join("")
      .trim() ?? "";
    return parseEstimate(text);
  } catch (err) {
    console.error("estimateOne error:", err instanceof Error ? err.message : err);
    return null;
  }
}

/// Tolerant JSON extraction + shape validation. Returns null on anything
/// malformed so bad model output is never shown as garbage (Session 6 check).
export function parseEstimate(text: string): EstimateFields | null {
  let cleaned = text.trim();
  const fence = cleaned.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) cleaned = fence[1].trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start === -1 || end === -1) return null;
  cleaned = cleaned.slice(start, end + 1);

  try {
    const o = JSON.parse(cleaned);
    const n = (v: unknown) => (typeof v === "number" && isFinite(v) ? v : null);
    const fields = {
      calories_low: n(o.calories_low),
      calories_high: n(o.calories_high),
      protein_low: n(o.protein_low),
      protein_high: n(o.protein_high),
      carbs_low: n(o.carbs_low),
      carbs_high: n(o.carbs_high),
      sugar_low: n(o.sugar_low),
      sugar_high: n(o.sugar_high),
      fat_low: n(o.fat_low),
      fat_high: n(o.fat_high),
    };
    // Require at least a calorie range to consider the estimate usable.
    if (fields.calories_low === null || fields.calories_high === null) return null;
    return {
      ...(fields as Record<string, number>),
      tags: Array.isArray(o.tags) ? o.tags.filter((t: unknown) => typeof t === "string") : [],
      reasoning: typeof o.reasoning === "string" ? o.reasoning : "",
    } as EstimateFields;
  } catch {
    return null;
  }
}
