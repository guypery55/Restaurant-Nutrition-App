// resolve-restaurant (Session 2) — Google Places proxy + canonical upsert.
//
// The Places key stays server-side: the client never calls Google directly.
// Two actions over one POST endpoint:
//   { action: "autocomplete", input, lat?, lng? }
//       → Places Autocomplete (New). Returns candidate predictions the user
//         disambiguates by branch. No DB write.
//   { action: "select", placeId }
//       → Place Details (New), then UPSERT into `restaurants` on place_id
//         (the canonical cache key). Returns the stored row.
//
// Uses Places API (New): https://places.googleapis.com/v1/...
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { adminClient } from "../_shared/supabase.ts";

const PLACES_BASE = "https://places.googleapis.com/v1";

interface AutocompleteBody {
  action: "autocomplete";
  input: string;
  lat?: number;
  lng?: number;
}

interface SelectBody {
  action: "select";
  placeId: string;
}

type RequestBody = AutocompleteBody | SelectBody;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Use POST." }, 405);
  }

  const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
  if (!apiKey) {
    return jsonResponse(
      { ok: false, error: "GOOGLE_PLACES_API_KEY is not configured." },
      500,
    );
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ ok: false, error: "Invalid JSON body." }, 400);
  }

  try {
    switch (body.action) {
      case "autocomplete":
        return await handleAutocomplete(body, apiKey);
      case "select":
        return await handleSelect(body, apiKey);
      default:
        return jsonResponse(
          { ok: false, error: "Unknown action. Expected 'autocomplete' or 'select'." },
          400,
        );
    }
  } catch (err) {
    console.error("resolve-restaurant error:", err);
    return jsonResponse(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      502,
    );
  }
});

/// Places Autocomplete (New): typed text → ranked candidate predictions.
async function handleAutocomplete(
  body: AutocompleteBody,
  apiKey: string,
): Promise<Response> {
  const input = (body.input ?? "").trim();
  if (input.length === 0) {
    // Empty input is not an error — just no candidates.
    return jsonResponse({ ok: true, candidates: [] });
  }

  const payload: Record<string, unknown> = {
    input,
    // Hebrew labels where available; the API still matches Latin/Hebrew input.
    languageCode: "he",
    regionCode: "IL",
    // Restaurants and other food/drink places.
    includedPrimaryTypes: ["restaurant", "cafe", "bar", "meal_takeaway"],
  };
  if (typeof body.lat === "number" && typeof body.lng === "number") {
    // The client knows where the user is → bias toward them (soft, 30 km).
    payload.locationBias = {
      circle: {
        center: { latitude: body.lat, longitude: body.lng },
        radius: 30000,
      },
    };
  } else {
    // No client location → restrict to Israel. Without this the API ranks
    // globally and bare terms (e.g. "ארומה", "pizza") return foreign places or
    // query-predictions with no place_id. This app is Israel-only, so a hard
    // country box is the right default.
    payload.locationRestriction = {
      rectangle: {
        low: { latitude: 29.45, longitude: 34.26 },
        high: { latitude: 33.34, longitude: 35.90 },
      },
    };
  }

  const res = await fetch(`${PLACES_BASE}/places:autocomplete`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Places autocomplete failed (${res.status}): ${detail}`);
  }

  const data = await res.json();
  const suggestions: unknown[] = Array.isArray(data.suggestions)
    ? data.suggestions
    : [];

  const candidates = suggestions
    .map((s) => (s as Record<string, any>).placePrediction)
    .filter((p) => p && p.placeId)
    .map((p) => ({
      placeId: p.placeId as string,
      // Primary line (usually the name) + the full formatted text.
      name: p.structuredFormat?.mainText?.text ?? p.text?.text ?? "",
      address: p.structuredFormat?.secondaryText?.text ?? "",
      fullText: p.text?.text ?? "",
    }));

  return jsonResponse({ ok: true, candidates });
}

/// Place Details (New) for the chosen place_id, then upsert the canonical row.
async function handleSelect(
  body: SelectBody,
  apiKey: string,
): Promise<Response> {
  const placeId = (body.placeId ?? "").trim();
  if (placeId.length === 0) {
    return jsonResponse({ ok: false, error: "Missing placeId." }, 400);
  }

  const res = await fetch(`${PLACES_BASE}/places/${encodeURIComponent(placeId)}`, {
    method: "GET",
    headers: {
      "X-Goog-Api-Key": apiKey,
      // Field mask keeps the request cheap — only what we store. websiteUri is
      // Session 3's primary menu-retrieval seed (the official site).
      "X-Goog-FieldMask":
        "id,displayName,formattedAddress,location,websiteUri",
      "Accept-Language": "he",
    },
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Place details failed (${res.status}): ${detail}`);
  }

  const place = await res.json();
  const canonicalPlaceId: string = place.id ?? placeId;
  const name: string = place.displayName?.text ?? "";
  const address: string | null = place.formattedAddress ?? null;
  const lat: number | null = place.location?.latitude ?? null;
  const lng: number | null = place.location?.longitude ?? null;
  const website: string | null = place.websiteUri ?? null;

  const db = adminClient();
  // Upsert on place_id (unique) so re-selecting the same branch never dupes.
  const { data: row, error } = await db
    .from("restaurants")
    .upsert(
      { place_id: canonicalPlaceId, name, address, lat, lng, website },
      { onConflict: "place_id" },
    )
    .select()
    .single();

  if (error) {
    throw new Error(`Upsert into restaurants failed: ${error.message}`);
  }

  return jsonResponse({ ok: true, restaurant: row });
}
