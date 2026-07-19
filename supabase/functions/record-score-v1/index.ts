import { createAdminClient } from "../_shared/admin.ts";
import {
  failure,
  isApiEnvelope,
  isErrorEnvelope,
  isObject,
  requestId,
  response,
  success,
} from "../_shared/api-v1.ts";
import { dispatchLiveActivityUpdateV1 } from "../_shared/activity-dispatch-v1.ts";
import { AuthError, requireUser } from "../_shared/auth.ts";
import { recomputeLatestCanonicalSnapshotV1 } from "../_shared/canonical-snapshot-v1.ts";
import { handleOptions } from "../_shared/cors.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function integerIn(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) &&
    value >= minimum && value <= maximum;
}

function statusFor(code: string): number {
  if (code === "unauthenticated") return 401;
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

  let accepted: Record<string, unknown> | null = null;
  try {
    const user = await requireUser(req);
    const body: unknown = await req.json().catch(() => null);
    if (
      !isObject(body) || body.schemaVersion !== 1 ||
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
        "A valid score, original revision, and idempotency key are required.",
      );
    }

    const admin = createAdminClient();
    const { data, error } = await admin.rpc(
      "record_authenticated_hole_score_service_v1",
      {
        p_actor_user_id: user.id,
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
      console.error("Authenticated score RPC failed", {
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
      !integerIn(data.data.acceptedRevision, 0, Number.MAX_SAFE_INTEGER)
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

    const canonical = await recomputeLatestCanonicalSnapshotV1(
      admin,
      data.data.tripId,
      data.data.acceptedRevision,
    );
    const activityDispatch = await dispatchLiveActivityUpdateV1(
      data.data.tripId,
      canonical.revision,
    );
    return success(id, {
      tripId: data.data.tripId,
      scoreId: data.data.scoreId,
      acceptedRevision: data.data.acceptedRevision,
      revision: canonical.revision,
      idempotentReplay: data.data.idempotentReplay === true,
      score: {
        roundId: body.roundId,
        tripPlayerId: body.tripPlayerId,
        holeNumber: body.holeNumber,
        strokes: body.strokes,
        penalties: body.penalties,
        grossTotal: body.strokes + body.penalties,
      },
      snapshot: canonical.snapshot,
      activityDispatch,
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return failure(id, 401, "unauthenticated", "Sign in is required.");
    }
    console.error("record-score-v1 failed", { requestId: id, error });
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
