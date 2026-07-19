import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.89.0";

export function createAdminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  }
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "X-Client-Info": "teecircle-edge-v1" } },
  });
}
