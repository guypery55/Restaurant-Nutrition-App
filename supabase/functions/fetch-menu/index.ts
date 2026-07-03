// fetch-menu (Session 3, build plan v2) — thin wrapper around the shared
// acquisition module. Cache-check first (the instant, free, 99% path once
// seeded); on a miss, acquire inline via Jina→Firecrawl→grounded-parse within a
// hard time budget, store it, or return "not_covered" (→ "we don't have this
// one yet"). Never invents a menu. All keys stay server-side (principle #1).
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { adminClient } from "../_shared/supabase.ts";
import { acquireMenu } from "../_shared/acquire/index.ts";

const FRESHNESS_DAYS = 30;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Use POST." }, 405);
  }

  let restaurantId: string;
  let force = false;
  let debug = false;
  try {
    const body = await req.json();
    restaurantId = (body.restaurant_id ?? "").trim();
    force = body.force === true; // bypass cache (testing / re-seed)
    debug = body.debug === true; // include the acquisition trace
  } catch {
    return jsonResponse({ ok: false, error: "Invalid JSON body." }, 400);
  }
  if (!restaurantId) {
    return jsonResponse({ ok: false, error: "Missing restaurant_id." }, 400);
  }

  const db = adminClient();

  try {
    const { data: restaurant, error: rErr } = await db
      .from("restaurants")
      .select("id, place_id, name, address, website")
      .eq("id", restaurantId)
      .single();
    if (rErr || !restaurant) {
      return jsonResponse({ ok: false, error: "Restaurant not found." }, 404);
    }

    // Cache check — a fresh stored menu wins, no scrape/model call.
    const { data: existingMenu } = await db
      .from("menus")
      .select("id, fetched_at, source, scraper, source_url, verified")
      .eq("restaurant_id", restaurantId)
      .maybeSingle();
    if (existingMenu && !force) {
      const ageMs = Date.now() - new Date(existingMenu.fetched_at).getTime();
      if (ageMs < FRESHNESS_DAYS * 24 * 60 * 60 * 1000) {
        const { data: dishes } = await db
          .from("dishes")
          .select("*")
          .eq("menu_id", existingMenu.id);
        return jsonResponse({
          ok: true,
          found: true,
          cached: true,
          menu_id: existingMenu.id,
          source: existingMenu.source,
          scraper: existingMenu.scraper,
          source_url: existingMenu.source_url,
          fetched_at: existingMenu.fetched_at,
          verified: existingMenu.verified === true,
          dishes: dishes ?? [],
        });
      }
    }

    // Miss → acquire inline (bounded).
    const result = await acquireMenu(db, restaurant);
    if (result.status === "found") {
      return jsonResponse({
        ok: true,
        found: true,
        cached: false,
        menu_id: result.menu_id,
        source: "web",
        scraper: result.scraper,
        source_url: result.source_url,
        // A freshly acquired web menu is never human-verified yet (S11 flips it).
        verified: false,
        dishes: result.dishes,
        ...(debug ? { trace: result.trace } : {}),
      });
    }
    return jsonResponse({
      ok: true,
      found: false,
      cached: false,
      reason: result.reason,
      note: "Not covered yet — logged to menu_requests.",
      ...(debug ? { trace: result.trace } : {}),
    });
  } catch (err) {
    console.error("fetch-menu error:", err);
    return jsonResponse(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      502,
    );
  }
});
