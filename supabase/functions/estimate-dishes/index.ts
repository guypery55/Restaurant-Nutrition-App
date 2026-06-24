// estimate-dishes (Session 6, build plan v2) — thin wrapper around the shared
// estimation module. Receives selected dish_ids, reuses cached dish_estimates
// where present (consistency — numbers never wobble), otherwise calls the Haiku
// estimator and stores the result. Returns per-dish nutrition ranges. Same
// module the Session 4 seed batch calls. All keys stay server-side (principle #1).
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { adminClient } from "../_shared/supabase.ts";
import { estimateDishes } from "../_shared/estimate/index.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Use POST." }, 405);
  }

  let dishIds: string[];
  try {
    const body = await req.json();
    dishIds = Array.isArray(body.dish_ids) ? body.dish_ids : [];
  } catch {
    return jsonResponse({ ok: false, error: "Invalid JSON body." }, 400);
  }
  if (dishIds.length === 0) {
    return jsonResponse({ ok: false, error: "Provide dish_ids: string[]." }, 400);
  }

  try {
    const db = adminClient();
    const estimates = await estimateDishes(db, dishIds);
    return jsonResponse({ ok: true, count: estimates.length, estimates });
  } catch (err) {
    console.error("estimate-dishes error:", err);
    return jsonResponse(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      502,
    );
  }
});
