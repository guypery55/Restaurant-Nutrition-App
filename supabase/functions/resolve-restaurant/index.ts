// resolve-restaurant — Session 0 stub (optional Places proxy).
//
// Real behavior (Session 2): proxy Google Places Autocomplete / Text Search so
// the Places key stays server-side, returning candidate restaurants the user
// disambiguates by branch. The chosen place_id becomes the canonical cache key.

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const secrets = {
    GOOGLE_PLACES_API_KEY: Boolean(Deno.env.get("GOOGLE_PLACES_API_KEY")),
  };

  return jsonResponse({
    ok: true,
    function: "resolve-restaurant",
    session: 0,
    secretsPresent: secrets,
    note: "stub — Places resolution lands in Session 2",
  });
});
