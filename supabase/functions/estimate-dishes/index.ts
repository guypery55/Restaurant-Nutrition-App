// estimate-dishes — Session 0 stub.
//
// Real behavior (Session 6): receive selected dish_ids, reuse cached
// dish_estimates where present (consistency), otherwise call the estimator
// model and store the result. Returns per-dish nutrition ranges.

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const secrets = {
    ANTHROPIC_API_KEY: Boolean(Deno.env.get("ANTHROPIC_API_KEY")),
  };

  return jsonResponse({
    ok: true,
    function: "estimate-dishes",
    session: 0,
    secretsPresent: secrets,
    note: "stub — nutrition estimation lands in Session 6",
  });
});
