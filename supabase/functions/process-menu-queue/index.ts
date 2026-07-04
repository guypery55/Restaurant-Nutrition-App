// process-menu-queue (Session 9, build plan v3) — the background acquisition
// worker. Drains public.menu_jobs OFF the request path: for each queued
// restaurant it runs the shared acquisition pipeline with a LONG budget (heavy
// multi-page / slow sites that time out the live try get acquired here), then
// AUTO-RUNS the estimator on the new dishes so a freshly covered menu is
// instantly usable. Marks each job done / failed and caps retries.
//
// Triggered two ways, both authorized by a shared secret in the `x-queue-secret`
// header (never a user JWT — verify_jwt is off, auth is this check):
//   1. fetch-menu kicks it immediately after enqueuing a live-try timeout.
//   2. pg_cron ticks it every minute (drains freshness re-enqueues + retries)
//      reading the secret from Vault.
import { jsonResponse } from "../_shared/cors.ts";
import { adminClient } from "../_shared/supabase.ts";
import { type AcquireRestaurant, acquireMenu } from "../_shared/acquire/index.ts";
import { estimateDishes } from "../_shared/estimate/index.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Longer than fetch-menu's ~55s live try — this is why the queue exists.
const WORKER_BUDGET_MS = 110_000;
// Overall wall-clock guard (the hard edge limit is ~150s); leave headroom.
const OVERALL_MS = 145_000;
// Don't start another job unless this much time remains for a useful acquire.
const MIN_SLOT_MS = 30_000;
// Retries for a job that keeps TIMING OUT (a genuine miss fails immediately).
const MAX_ATTEMPTS = 3;

interface MenuJob {
  id: string;
  restaurant_id: string;
  status: string;
  attempts: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });

  // Auth: shared secret. fetch-menu sends it from its env; cron from Vault.
  const secret = Deno.env.get("QUEUE_WORKER_SECRET");
  const provided = req.headers.get("x-queue-secret");
  if (!secret || provided !== secret) {
    return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  }

  // Optional { wait: true } → await the drain and return a summary (used by the
  // end-to-end test). Default: respond immediately, drain in the background so
  // the caller (the kick) isn't held open.
  let wait = false;
  try {
    const body = await req.json();
    wait = body?.wait === true;
  } catch { /* no body — fine */ }

  const db = adminClient();
  const work = processQueue(db);

  if (wait) {
    const summary = await work;
    return jsonResponse({ ok: true, ...summary });
  }
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(work);
  else await work; // local / no edge runtime
  return jsonResponse({ ok: true, accepted: true });
});

/// Claim + process jobs until the queue is empty or we're low on wall clock.
async function processQueue(db: SupabaseClient) {
  const start = Date.now();
  const done: string[] = [];
  const failed: string[] = [];
  const requeued: string[] = [];

  while (true) {
    const remaining = OVERALL_MS - (Date.now() - start);
    if (remaining < MIN_SLOT_MS) break;

    const { data: jobs, error } = await db.rpc("claim_menu_jobs", { batch: 1 });
    if (error) {
      console.error("claim_menu_jobs failed:", error.message);
      break;
    }
    const job = (jobs as MenuJob[] | null)?.[0];
    if (!job) break; // queue drained

    const budget = Math.min(WORKER_BUDGET_MS, remaining - 8_000);
    await processJob(db, job, budget, { done, failed, requeued });
  }

  return { done, failed, requeued, ms: Date.now() - start };
}

async function processJob(
  db: SupabaseClient,
  job: MenuJob,
  budgetMs: number,
  out: { done: string[]; failed: string[]; requeued: string[] },
) {
  const { data: restaurant } = await db
    .from("restaurants")
    .select("id, place_id, name, address, website")
    .eq("id", job.restaurant_id)
    .single();

  if (!restaurant) {
    await setStatus(db, job.id, "failed", "restaurant_gone");
    out.failed.push(job.restaurant_id);
    return;
  }
  const r = restaurant as AcquireRestaurant;

  try {
    const result = await acquireMenu(db, r, { budgetMs });

    if (result.status === "found") {
      // Auto-estimate the new dishes so the menu is usable the moment it lands.
      // estimateDishes is cached/idempotent, so a partial run (if we run low on
      // time) is safe — the rest fill on demand at the first basket check.
      const dishIds = (result.dishes ?? [])
        .map((d) => (d as { id?: string }).id)
        .filter((id): id is string => typeof id === "string");
      if (dishIds.length) {
        try {
          await estimateDishes(db, dishIds);
        } catch (e) {
          console.error(`auto-estimate failed for ${r.name}:`, e);
        }
      }
      await setStatus(db, job.id, "done", null);
      out.done.push(r.name);
      return;
    }

    // not_covered. A TIMEOUT is worth retrying (heavy site, transient); a
    // genuine miss (no_website / platform_only / no_menu_found) is not — and
    // acquireMenu already logged it to menu_requests.
    const reason = result.reason;
    if (reason === "timeout" && job.attempts < MAX_ATTEMPTS) {
      await setStatus(db, job.id, "pending", reason);
      out.requeued.push(r.name);
    } else {
      if (reason === "timeout") await logMiss(db, r, "timeout"); // retries spent
      await setStatus(db, job.id, "failed", reason ?? "unknown");
      out.failed.push(r.name);
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`process job ${job.id} (${r.name}) errored:`, msg);
    if (job.attempts < MAX_ATTEMPTS) {
      await setStatus(db, job.id, "pending", "error", msg);
      out.requeued.push(r.name);
    } else {
      await setStatus(db, job.id, "failed", "error", msg);
      out.failed.push(r.name);
    }
  }
}

async function setStatus(
  db: SupabaseClient,
  id: string,
  status: string,
  reason: string | null,
  lastError?: string,
) {
  const patch: Record<string, unknown> = {
    status,
    reason,
    updated_at: new Date().toISOString(),
  };
  if (lastError !== undefined) patch.last_error = lastError;
  const { error } = await db.from("menu_jobs").update(patch).eq("id", id);
  if (error) console.error(`menu_jobs update (${id} -> ${status}) failed:`, error.message);
}

async function logMiss(db: SupabaseClient, r: AcquireRestaurant, reason: string) {
  try {
    await db.from("menu_requests").insert({
      place_id: r.place_id ?? null,
      name: r.name,
      reason,
    });
  } catch { /* best-effort */ }
}
