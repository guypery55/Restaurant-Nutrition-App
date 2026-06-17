// fetch-menu — Session 0 stub.
//
// Real behavior (Session 3): given a resolved restaurant, check the menu cache,
// otherwise web-search → fetch → grounded-parse → store the menu and dishes.
// For now it just proves the function runs and can read its secrets server-side
// (the client must never hold these keys).

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Read secrets WITHOUT leaking their values — report presence only.
  const secrets = {
    ANTHROPIC_API_KEY: Boolean(Deno.env.get("ANTHROPIC_API_KEY")),
    SEARCH_API_KEY: Boolean(Deno.env.get("SEARCH_API_KEY")),
  };

  return jsonResponse({
    ok: true,
    function: "fetch-menu",
    session: 0,
    secretsPresent: secrets,
    note: "stub — menu fetch/parse lands in Session 3",
  });
});
