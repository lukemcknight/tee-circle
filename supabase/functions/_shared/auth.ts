// Supabase auth guard: every function requires a signed-in user.

import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.89.0";

export class AuthError extends Error {
  override name = "AuthError";
  readonly status = 401;
}

export function createUserClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new AuthError("Missing Authorization header");
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    },
  );
}

/**
 * Validate the caller's JWT and return the user, throwing AuthError (401)
 * when the request is anonymous or the token is invalid.
 *
 * SUPABASE_URL and SUPABASE_ANON_KEY are injected by the Supabase platform —
 * no secrets to configure for this.
 */
export async function requireUser(req: Request) {
  const supabase = createUserClient(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user) {
    throw new AuthError("Invalid or expired token");
  }
  return data.user;
}
