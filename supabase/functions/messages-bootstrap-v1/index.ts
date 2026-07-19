import { createAdminClient } from "../_shared/admin.ts";
import {
  failure,
  isApiEnvelope,
  isErrorEnvelope,
  isObject,
  requestId,
  response,
} from "../_shared/api-v1.ts";
import { handleOptions } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/crypto.ts";

const SESSION_PATTERN = /^[A-Za-z0-9_-]{40,128}$/;

function bearerToken(req: Request): string | null {
  const match = req.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i);
  const token = match?.[1]?.trim() ?? "";
  return SESSION_PATTERN.test(token) ? token : null;
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  const id = requestId();
  if (req.method !== "POST") {
    return failure(
      id,
      405,
      "method_not_allowed",
      "Use POST for Messages bootstrap.",
    );
  }
  const token = bearerToken(req);
  if (!token) {
    return failure(
      id,
      401,
      "extension_session_expired",
      "Open TeeCircle to reconnect Messages.",
    );
  }
  const body: unknown = await req.json().catch(() => ({}));
  if (
    !isObject(body) ||
    (body.schemaVersion !== undefined && body.schemaVersion !== 1)
  ) {
    return failure(
      id,
      400,
      "invalid_request",
      "Request must use schemaVersion 1.",
    );
  }

  try {
    const admin = createAdminClient();
    const { data, error } = await admin.rpc(
      "get_messages_bootstrap_service_v1",
      {
        p_token_hash_hex: await sha256Hex(token),
      },
    );
    if (error) {
      console.error("Messages bootstrap RPC failed", {
        requestId: id,
        error: error.message,
      });
      return failure(
        id,
        503,
        "service_unavailable",
        "Messages could not refresh this trip.",
        true,
      );
    }
    if (!isApiEnvelope(data)) {
      return failure(
        id,
        503,
        "invalid_server_response",
        "Messages could not refresh this trip.",
        true,
      );
    }
    const status = isErrorEnvelope(data)
      ? data.error.code === "extension_session_expired" ? 401 : 400
      : 200;
    return response(data, status);
  } catch (error) {
    console.error("messages-bootstrap-v1 failed", { requestId: id, error });
    return failure(
      id,
      500,
      "internal_error",
      "Messages could not refresh this trip.",
      true,
    );
  }
});
