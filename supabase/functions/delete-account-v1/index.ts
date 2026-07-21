import { createAdminClient } from "../_shared/admin.ts";
import { accountDeletionStatusFor } from "../_shared/account-deletion-v1.ts";
import {
  failure,
  isApiEnvelope,
  isErrorEnvelope,
  isObject,
  requestId,
  response,
  success,
} from "../_shared/api-v1.ts";
import { AuthError, createUserClient, requireUser } from "../_shared/auth.ts";
import { handleOptions } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  const id = requestId();
  if (req.method !== "POST") {
    return failure(id, 405, "method_not_allowed", "Use POST to delete an account.");
  }

  try {
    const user = await requireUser(req);
    const body: unknown = await req.json().catch(() => null);
    if (!isObject(body) || body.schemaVersion !== 1) {
      return failure(id, 400, "invalid_request", "A schemaVersion 1 body is required.");
    }

    // The destructive data pass runs as the caller so auth.uid() semantics
    // match the SQL command's own checks.
    const supabase = createUserClient(req);
    const { data, error } = await supabase.rpc("finalize_account_deletion_v1");
    if (error) {
      console.error("finalize_account_deletion_v1 failed", {
        requestId: id,
        error: error.message,
      });
      return failure(id, 503, "service_unavailable", "The account could not be deleted.", true);
    }
    if (!isApiEnvelope(data)) {
      return failure(
        id,
        503,
        "invalid_server_response",
        "The account could not be deleted.",
        true,
      );
    }
    if (isErrorEnvelope(data)) {
      return response(data, accountDeletionStatusFor(data.error.code));
    }

    // Only the service role can remove the auth user; SQL cannot.
    const admin = createAdminClient();
    const { error: authError } = await admin.auth.admin.deleteUser(user.id);
    if (authError) {
      console.error("auth user deletion failed", {
        requestId: id,
        error: authError.message,
      });
      // Retryable: the data pass already committed, so legacy PII tables that
      // cascade off auth.users (player_handicap_profiles, scorecards/
      // scorecard_holes, handicap_differentials) persist until a retry
      // succeeds in actually removing the auth.users row.
      return failure(
        id,
        503,
        "auth_deletion_incomplete",
        "Your data was removed, but sign-in cleanup is still finishing. Try again.",
        true,
      );
    }
    return success(id, { deleted: true });
  } catch (error) {
    if (error instanceof AuthError) {
      return failure(id, 401, "unauthenticated", "Sign in is required.");
    }
    console.error("delete-account-v1 failed", { requestId: id, error });
    return failure(id, 500, "internal_error", "The account could not be deleted.", true);
  }
});
