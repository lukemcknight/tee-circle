// Supabase auth guard: every function requires a signed-in user.

import { createClient } from "@supabase/supabase-js";

export class AuthError extends Error {
  override name = "AuthError";
  readonly status = 401;
}

/**
 * Validate the caller's JWT and return the user, throwing AuthError (401)
 * when the request is anonymous or the token is invalid.
 *
 * SUPABASE_URL and SUPABASE_ANON_KEY are injected by the Supabase platform —
 * no secrets to configure for this.
 */
export async function requireUser(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new AuthError("Missing Authorization header");
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user) {
    throw new AuthError("Invalid or expired token");
  }
  return data.user;
}
