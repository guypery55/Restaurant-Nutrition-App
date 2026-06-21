// Shared service-role Supabase client for Edge Functions.
//
// Uses the SERVICE ROLE key, which bypasses Row Level Security — this is why
// all privileged writes (upserting restaurants, storing menus/estimates) happen
// here in functions and never in the Flutter client (principle #1). The URL and
// service-role key are auto-injected into the function runtime by Supabase.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    throw new Error(
      "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set in the function runtime.",
    );
  }
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
