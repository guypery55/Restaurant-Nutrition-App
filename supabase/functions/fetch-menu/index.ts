// fetch-menu (Session 3, build plan v2; queue handoff added Session 9 v3) —
// thin wrapper around the shared acquisition module.
//
// Order: (1) cache-check — a fresh stored menu wins, instant + free (the 99%
// path once seeded). (2) On a miss, if the background worker is already on this
// place (or just gave up), report that. (3) Otherwise try to acquire LIVE within
// a tight budget while the user waits. (4) If that budget is exceeded, hand the
// job to the background queue and return "pending" ("we're working on it — check
// back in a few minutes") instead of dropping it. Never invents a menu. All keys
// stay server-side (principle #1).
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { adminClient } from "../_shared/supabase.ts";
import { acquireMenu } from "../_shared/acquire/index.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const FRESHNESS_DAYS = 30;
// A genuinely menu-less site (failed background job) is not re-attempted for
// this long — don't burn Jina/Firecrawl/Claude re-checking known-dead sites on
// every visit. After the cooldown a re-visit is allowed to try live again (the
// site may have changed).
const FAILED_COOLDOWN_DAYS = 7;

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

    // Cache check — a stored menu wins, no scrape/model call. We serve it even
    // when STALE: a slightly-old menu beats making the user wait, and (Session 9)
    // if it's stale we enqueue a background refresh so it's fresh next time —
    // never dropping the user to a "pending" screen when usable data exists.
    const { data: existingMenu } = await db
      .from("menus")
      .select("id, fetched_at, source, scraper, source_url, verified")
      .eq("restaurant_id", restaurantId)
      .maybeSingle();
    if (existingMenu && !force) {
      const ageMs = Date.now() - new Date(existingMenu.fetched_at).getTime();
      const fresh = ageMs < FRESHNESS_DAYS * 24 * 60 * 60 * 1000;
      if (!fresh) await enqueueAndKick(db, restaurantId); // idempotent bg refresh
      const { data: dishes } = await db
        .from("dishes")
        .select("*")
        .eq("menu_id", existingMenu.id);
      return jsonResponse({
        ok: true,
        found: true,
        cached: fresh,
        menu_id: existingMenu.id,
        source: existingMenu.source,
        scraper: existingMenu.scraper,
        source_url: existingMenu.source_url,
        fetched_at: existingMenu.fetched_at,
        verified: existingMenu.verified === true,
        dishes: dishes ?? [],
      });
    }

    // Miss. Is the background worker already handling this place (or did it just
    // give up)? If so, report that instead of racing another live fetch.
    const job = await latestJob(db, restaurantId);
    if (job && (job.status === "pending" || job.status === "processing")) {
      return pendingResponse();
    }
    if (job && job.status === "failed" && !force && isRecent(job.updated_at, FAILED_COOLDOWN_DAYS)) {
      return notCoveredResponse(job.reason ?? "no_menu_found");
    }

    // No one's on it → try to acquire LIVE within the tight budget (the user is
    // waiting on a spinner).
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
    // Taking too long → hand off to the background worker (which retries with a
    // longer budget + auto-estimates) and tell the user we're on it. A genuine
    // miss (no_website / platform_only / no_menu_found) is final — acquireMenu
    // already logged it to menu_requests, so report "not covered" as before.
    if (result.reason === "timeout") {
      await enqueueAndKick(db, restaurantId);
      return pendingResponse(debug ? result.trace : undefined);
    }
    return notCoveredResponse(result.reason, debug ? result.trace : undefined);
  } catch (err) {
    console.error("fetch-menu error:", err);
    return jsonResponse(
      { ok: false, error: err instanceof Error ? err.message : String(err) },
      502,
    );
  }
});

interface JobRow {
  status: string;
  reason: string | null;
  updated_at: string;
}

/// The most recent acquisition job for a restaurant (or null if never queued).
async function latestJob(db: SupabaseClient, restaurantId: string): Promise<JobRow | null> {
  const { data } = await db
    .from("menu_jobs")
    .select("status, reason, updated_at")
    .eq("restaurant_id", restaurantId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data as JobRow | null) ?? null;
}

function isRecent(iso: string, days: number): boolean {
  return Date.now() - new Date(iso).getTime() < days * 24 * 60 * 60 * 1000;
}

/// Enqueue a background acquisition job (idempotent — the partial unique index
/// blocks a second active job for the same place) and kick the worker so it
/// starts now rather than waiting for the next cron tick.
async function enqueueAndKick(db: SupabaseClient, restaurantId: string): Promise<void> {
  const { error } = await db.from("menu_jobs").insert({ restaurant_id: restaurantId });
  // 23505 = a concurrent request already queued this place — fine, still pending.
  if (error && !error.message.toLowerCase().includes("duplicate") && error.code !== "23505") {
    console.error("enqueue failed:", error.message);
    return; // couldn't enqueue → don't bother kicking
  }
  await kickWorker();
}

/// Fire the worker via its public URL, authorized by the shared secret. The
/// worker responds immediately and drains in its own background, so this returns
/// fast; wrapped in waitUntil so the kick isn't cut when we return to the client.
async function kickWorker(): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const secret = Deno.env.get("QUEUE_WORKER_SECRET");
  if (!url || !secret) {
    console.error("kickWorker: SUPABASE_URL / QUEUE_WORKER_SECRET not set");
    return;
  }
  const kick = fetch(`${url}/functions/v1/process-menu-queue`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-queue-secret": secret },
    body: "{}",
  }).then(() => {}).catch((e) => console.error("worker kick failed:", e));

  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(kick);
  else await kick;
}

/// "We're fetching this one now — check back in a few minutes." The client turns
/// this into calm Hebrew and auto-polls until the menu lands.
function pendingResponse(trace?: unknown): Response {
  return jsonResponse({
    ok: true,
    found: false,
    pending: true,
    note: "Acquiring this menu in the background — check back shortly.",
    ...(trace ? { trace } : {}),
  });
}

function notCoveredResponse(reason: string | undefined, trace?: unknown): Response {
  return jsonResponse({
    ok: true,
    found: false,
    pending: false,
    reason,
    note: "Not covered yet — logged to menu_requests.",
    ...(trace ? { trace } : {}),
  });
}
