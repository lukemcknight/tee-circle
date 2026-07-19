import { createAdminClient } from "../_shared/admin.ts";
import { dispatchLiveActivityUpdateV1 } from "../_shared/activity-dispatch-v1.ts";
import {
  failure,
  isApiEnvelope,
  isErrorEnvelope,
  isObject,
  requestId,
  response,
  success,
} from "../_shared/api-v1.ts";
import { handleOptions } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/crypto.ts";
import { recomputeLatestCanonicalSnapshotV1 } from "../_shared/canonical-snapshot-v1.ts";

const SESSION_PATTERN = /^[A-Za-z0-9_-]{40,128}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function bearerToken(req: Request): string | null {
  const match = req.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i);
  const token = match?.[1]?.trim() ?? "";
  return SESSION_PATTERN.test(token) ? token : null;
}

function integerIn(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return typeof value === "number" && Number.isInteger(value) &&
    value >= minimum && value <= maximum;
}

function statusFor(code: string): number {
  if (code === "extension_session_expired") return 401;
  if (code === "forbidden") return 403;
  if (code === "round_not_found" || code === "hole_not_found") return 404;
  if (
    code === "score_conflict" || code === "score_write_conflict" ||
    code === "idempotency_key_reused"
  ) return 409;
  if (code === "native_writes_disabled") return 503;
  return 400;
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  const id = requestId();
  if (req.method !== "POST") {
    return failure(id, 405, "method_not_allowed", "Use POST to save a score.");
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
  const body: unknown = await req.json().catch(() => null);
  if (
    !isObject(body) ||
    body.schemaVersion !== 1 ||
    typeof body.roundId !== "string" || !UUID_PATTERN.test(body.roundId) ||
    typeof body.tripPlayerId !== "string" ||
    !UUID_PATTERN.test(body.tripPlayerId) ||
    !integerIn(body.holeNumber, 1, 18) ||
    !integerIn(body.strokes, 1, 30) ||
    !integerIn(body.penalties, 0, 30) ||
    typeof body.idempotencyKey !== "string" ||
    !UUID_PATTERN.test(body.idempotencyKey) ||
    !integerIn(body.expectedScoreRevision, 0, Number.MAX_SAFE_INTEGER)
  ) {
    return failure(
      id,
      400,
      "invalid_request",
      "A valid hole score, original revision, and idempotency key are required.",
    );
  }

  let accepted: Record<string, unknown> | null = null;
  try {
    const admin = createAdminClient();
    const { data, error } = await admin.rpc(
      "record_extension_hole_score_service_v1",
      {
        p_token_hash_hex: await sha256Hex(token),
        p_round_id: body.roundId,
        p_trip_player_id: body.tripPlayerId,
        p_hole_number: body.holeNumber,
        p_strokes: body.strokes,
        p_penalties: body.penalties,
        p_idempotency_key: body.idempotencyKey,
        p_expected_score_revision: body.expectedScoreRevision,
      },
    );
    if (error) {
      console.error("Messages score RPC failed", {
        requestId: id,
        error: error.message,
      });
      return failure(
        id,
        503,
        "service_unavailable",
        "The score could not be saved.",
        true,
      );
    }
    if (!isApiEnvelope(data)) {
      return failure(
        id,
        503,
        "invalid_server_response",
        "The score could not be saved.",
        true,
      );
    }
    if (isErrorEnvelope(data)) {
      return response(data, statusFor(data.error.code));
    }
    if (
      !isObject(data.data) || typeof data.data.tripId !== "string" ||
      typeof data.data.scoreId !== "string" ||
      typeof data.data.acceptedRevision !== "number"
    ) {
      return failure(
        id,
        503,
        "invalid_server_response",
        "The score was accepted but standings could not be refreshed.",
        true,
      );
    }
    accepted = data.data;
    const result = await recomputeLatestCanonicalSnapshotV1(
      admin,
      data.data.tripId,
      data.data.acceptedRevision,
    );
    const activityDispatch = await dispatchLiveActivityUpdateV1(
      data.data.tripId,
      result.revision,
    );
    return success(id, {
      tripId: data.data.tripId,
      scoreId: data.data.scoreId,
      acceptedRevision: data.data.acceptedRevision,
      revision: result.revision,
      idempotentReplay: data.data.idempotentReplay === true,
      score: {
        roundId: body.roundId,
        tripPlayerId: body.tripPlayerId,
        holeNumber: body.holeNumber,
        strokes: body.strokes,
        penalties: body.penalties,
        grossTotal: body.strokes + body.penalties,
      },
      snapshot: result.snapshot,
      activityDispatch,
    });
  } catch (error) {
    console.error("score-trip-hole-v1 failed", { requestId: id, error });
    return accepted
      ? failure(
        id,
        503,
        "snapshot_updating",
        "Your score was saved, but the standings are still updating.",
        true,
        undefined,
        {
          tripId: accepted.tripId,
          scoreId: accepted.scoreId,
          acceptedRevision: accepted.acceptedRevision,
        },
      )
      : failure(
        id,
        500,
        "internal_error",
        "The score could not be saved.",
        true,
      );
  }
});
