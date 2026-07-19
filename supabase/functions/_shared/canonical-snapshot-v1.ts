import type { SupabaseClient } from "npm:@supabase/supabase-js@2.89.0";
import { isErrorEnvelope, isObject } from "./api-v1.ts";
import {
  buildLeaderboardSnapshotV1,
  type LeaderboardSnapshotV1,
  parseTripScoringInputV1,
} from "./tournament-v1.ts";

export const SCORING_ENGINE_VERSION = "tee-circle-ts-2";

export class SnapshotRecomputeError extends Error {
  override name = "SnapshotRecomputeError";

  constructor(
    readonly code: string,
    message: string,
    readonly currentRevision?: number,
  ) {
    super(message);
  }
}

export interface CanonicalSnapshotResultV1 {
  revision: number;
  snapshot: LeaderboardSnapshotV1;
}

async function recomputeRevision(
  admin: SupabaseClient,
  tripId: string,
  revision: number,
): Promise<CanonicalSnapshotResultV1> {
  const { data: inputEnvelope, error: inputError } = await admin.rpc(
    "get_trip_scoring_input_v1",
    { p_trip_id: tripId, p_revision: revision },
  );
  if (inputError) {
    throw new SnapshotRecomputeError(
      "scoring_input_failed",
      `scoring input RPC: ${inputError.message}`,
    );
  }
  if (isErrorEnvelope(inputEnvelope)) {
    throw new SnapshotRecomputeError(
      inputEnvelope.error.code,
      `scoring input: ${inputEnvelope.error.code}`,
      inputEnvelope.error.currentRevision,
    );
  }
  const input = isObject(inputEnvelope) && isObject(inputEnvelope.data)
    ? parseTripScoringInputV1(inputEnvelope.data)
    : null;
  if (!input) {
    throw new SnapshotRecomputeError(
      "invalid_scoring_input",
      "invalid scoring input contract",
    );
  }

  // A revision has one canonical broadcast value. Idempotent retries reuse it
  // instead of changing generatedAt or moment by rebuilding the same revision.
  const { data: existingRow, error: existingError } = await admin
    .from("trip_leaderboard_snapshots")
    .select("payload,scoring_engine_version")
    .eq("trip_id", tripId)
    .eq("revision", revision)
    .maybeSingle();
  if (existingError) {
    throw new SnapshotRecomputeError(
      "existing_snapshot_failed",
      `existing snapshot query: ${existingError.message}`,
    );
  }
  if (isObject(existingRow) && isObject(existingRow.payload)) {
    if (existingRow.scoring_engine_version !== SCORING_ENGINE_VERSION) {
      throw new SnapshotRecomputeError(
        "snapshot_engine_mismatch",
        "the current revision was computed by a different scoring engine",
        revision,
      );
    }
    const existing = existingRow.payload;
    if (
      existing.schemaVersion !== 1 || existing.revision !== revision ||
      existing.tripId !== input.trip.publicId
    ) {
      throw new SnapshotRecomputeError(
        "invalid_existing_snapshot",
        "existing canonical snapshot has an invalid identity",
      );
    }
    return {
      revision,
      snapshot: existing as unknown as LeaderboardSnapshotV1,
    };
  }

  const { data: priorRow, error: priorError } = await admin
    .from("trip_leaderboard_snapshots")
    .select("payload")
    .eq("trip_id", tripId)
    .lt("revision", revision)
    .order("revision", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (priorError) {
    throw new SnapshotRecomputeError(
      "prior_snapshot_failed",
      `prior snapshot query: ${priorError.message}`,
    );
  }
  const previous = isObject(priorRow) && isObject(priorRow.payload)
    ? priorRow.payload as unknown as LeaderboardSnapshotV1
    : null;
  const snapshot = buildLeaderboardSnapshotV1(input, previous);

  const { data: persistEnvelope, error: persistError } = await admin.rpc(
    "persist_trip_snapshot_v1",
    {
      p_trip_id: tripId,
      p_revision: revision,
      p_payload: snapshot,
      p_scoring_engine_version: SCORING_ENGINE_VERSION,
    },
  );
  if (persistError) {
    throw new SnapshotRecomputeError(
      "snapshot_persist_failed",
      `persist snapshot RPC: ${persistError.message}`,
    );
  }
  if (isErrorEnvelope(persistEnvelope)) {
    throw new SnapshotRecomputeError(
      persistEnvelope.error.code,
      `persist snapshot: ${persistEnvelope.error.code}`,
      persistEnvelope.error.currentRevision,
    );
  }
  // Persistence is insert-once. Re-read the row so concurrent workers always
  // return/broadcast the exact value that won the canonical revision race.
  const { data: canonicalRow, error: canonicalError } = await admin
    .from("trip_leaderboard_snapshots")
    .select("payload,scoring_engine_version")
    .eq("trip_id", tripId)
    .eq("revision", revision)
    .maybeSingle();
  if (
    canonicalError || !isObject(canonicalRow) ||
    !isObject(canonicalRow.payload)
  ) {
    throw new SnapshotRecomputeError(
      "canonical_snapshot_missing",
      canonicalError
        ? `canonical snapshot query: ${canonicalError.message}`
        : "canonical snapshot was not readable after persistence",
    );
  }
  const canonical = canonicalRow.payload;
  if (
    canonical.schemaVersion !== 1 || canonical.revision !== revision ||
    canonical.tripId !== input.trip.publicId ||
    canonicalRow.scoring_engine_version !== SCORING_ENGINE_VERSION
  ) {
    throw new SnapshotRecomputeError(
      "invalid_canonical_snapshot",
      "persisted canonical snapshot has an invalid identity",
    );
  }
  return {
    revision,
    snapshot: canonical as unknown as LeaderboardSnapshotV1,
  };
}

/** Compute exactly one revision. Scheduled repair uses this so stale jobs are
 * reported as superseded instead of silently moving to a different revision. */
export function recomputeCanonicalSnapshotRevisionV1(
  admin: SupabaseClient,
  tripId: string,
  revision: number,
): Promise<CanonicalSnapshotResultV1> {
  return recomputeRevision(admin, tripId, revision);
}

/** Score requests follow concurrent writes forward and return the latest
 * persisted authoritative snapshot. The score command itself still enforces
 * its caller-supplied expected revision before accepting a write. */
export async function recomputeLatestCanonicalSnapshotV1(
  admin: SupabaseClient,
  tripId: string,
  acceptedRevision: number,
  maximumAttempts = 5,
): Promise<CanonicalSnapshotResultV1> {
  let revision = acceptedRevision;
  for (let attempt = 0; attempt < maximumAttempts; attempt += 1) {
    try {
      return await recomputeRevision(admin, tripId, revision);
    } catch (error) {
      if (
        error instanceof SnapshotRecomputeError &&
        error.code === "stale_revision" &&
        typeof error.currentRevision === "number"
      ) {
        revision = error.currentRevision;
        continue;
      }
      throw error;
    }
  }
  throw new SnapshotRecomputeError(
    "revision_churn",
    "trip revision changed repeatedly during snapshot recomputation",
    revision,
  );
}
