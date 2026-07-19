import type { SupabaseClient } from "npm:@supabase/supabase-js@2.89.0";
import {
  recomputeLatestCanonicalSnapshotV1,
  SnapshotRecomputeError,
} from "./canonical-snapshot-v1.ts";

function assertEquals(actual: unknown, expected: unknown, label: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${label}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
}

Deno.test("idempotent score replay follows the trip to its latest snapshot", async () => {
  const requestedRevisions: number[] = [];
  const latestSnapshot = {
    schemaVersion: 1,
    tripId: "trip-public",
    revision: 43,
    status: "live",
    primaryFormat: "stableford",
    currentRound: null,
    boards: [],
    moment: { kind: "score_update", summary: "Standings updated" },
    generatedAt: "2026-07-13T18:42:10.125Z",
  };
  const scoringInput = {
    trip: {
      id: "00000000-0000-4000-8000-000000000001",
      publicId: "trip-public",
      name: "Trip",
      status: "live",
      enabledFormats: ["stableford"],
      primaryFormat: "stableford",
      scoringMode: "gross",
      revision: 43,
    },
    rounds: [],
  };
  const query = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    maybeSingle() {
      return {
        data: {
          payload: latestSnapshot,
          scoring_engine_version: "tee-circle-ts-2",
        },
        error: null,
      };
    },
  };
  const admin = {
    rpc(name: string, args: Record<string, unknown>) {
      if (name !== "get_trip_scoring_input_v1") {
        throw new Error(`unexpected RPC ${name}`);
      }
      const revision = args.p_revision as number;
      requestedRevisions.push(revision);
      if (revision === 42) {
        return {
          data: {
            schemaVersion: 1,
            requestId: "request-stale",
            error: {
              code: "stale_revision",
              message: "newer revision",
              retryable: true,
              currentRevision: 43,
            },
          },
          error: null,
        };
      }
      return {
        data: {
          schemaVersion: 1,
          requestId: "request-latest",
          data: scoringInput,
        },
        error: null,
      };
    },
    from(name: string) {
      if (name !== "trip_leaderboard_snapshots") {
        throw new Error(`unexpected table ${name}`);
      }
      return query;
    },
  } as unknown as SupabaseClient;

  const result = await recomputeLatestCanonicalSnapshotV1(admin, "trip-id", 42);
  assertEquals(requestedRevisions, [42, 43], "revision traversal");
  assertEquals(result.revision, 43, "returned revision");
  assertEquals(result.snapshot, latestSnapshot, "canonical snapshot reuse");
});

Deno.test("a current snapshot from another engine fails closed", async () => {
  const scoringInput = {
    trip: {
      id: "00000000-0000-4000-8000-000000000001",
      publicId: "trip-public",
      name: "Trip",
      status: "live",
      enabledFormats: ["stableford"],
      primaryFormat: "stableford",
      scoringMode: "gross",
      revision: 7,
    },
    rounds: [],
  };
  const query = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    maybeSingle() {
      return {
        data: {
          payload: {
            schemaVersion: 1,
            tripId: "trip-public",
            revision: 7,
          },
          scoring_engine_version: "tee-circle-ts-1",
        },
        error: null,
      };
    },
  };
  const admin = {
    rpc() {
      return {
        data: {
          schemaVersion: 1,
          requestId: "request-current",
          data: scoringInput,
        },
        error: null,
      };
    },
    from() {
      return query;
    },
  } as unknown as SupabaseClient;

  let caught: unknown;
  try {
    await recomputeLatestCanonicalSnapshotV1(admin, "trip-id", 7);
  } catch (error) {
    caught = error;
  }
  assertEquals(caught instanceof SnapshotRecomputeError, true, "error type");
  assertEquals(
    caught instanceof SnapshotRecomputeError ? caught.code : null,
    "snapshot_engine_mismatch",
    "error code",
  );
});
