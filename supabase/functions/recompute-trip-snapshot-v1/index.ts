import { createAdminClient } from "../_shared/admin.ts";
import { dispatchLiveActivityUpdateV1 } from "../_shared/activity-dispatch-v1.ts";
import { failure, isObject, requestId, success } from "../_shared/api-v1.ts";
import { timingSafeStringEqual } from "../_shared/crypto.ts";
import {
  recomputeCanonicalSnapshotRevisionV1,
  SCORING_ENGINE_VERSION,
  SnapshotRecomputeError,
} from "../_shared/canonical-snapshot-v1.ts";

interface SnapshotJob {
  tripId: string;
  revision: number;
}

function isJob(value: unknown): value is SnapshotJob {
  return isObject(value) &&
    typeof value.tripId === "string" &&
    typeof value.revision === "number" &&
    Number.isSafeInteger(value.revision) &&
    value.revision >= 0;
}

async function processJob(
  admin: ReturnType<typeof createAdminClient>,
  job: SnapshotJob,
): Promise<Record<string, unknown>> {
  try {
    const result = await recomputeCanonicalSnapshotRevisionV1(
      admin,
      job.tripId,
      job.revision,
    );
    const activityDispatch = await dispatchLiveActivityUpdateV1(
      job.tripId,
      job.revision,
    );
    return {
      tripId: job.tripId,
      revision: job.revision,
      status: "completed",
      moment: result.snapshot.moment.kind,
      activityDispatch,
    };
  } catch (error) {
    if (
      error instanceof SnapshotRecomputeError &&
      error.code === "stale_revision"
    ) {
      return {
        tripId: job.tripId,
        revision: job.revision,
        status: "superseded",
        currentRevision: error.currentRevision,
      };
    }
    const message = error instanceof Error ? error.message : String(error);
    console.error("snapshot job failed", { ...job, error: message });
    await admin.rpc("fail_trip_snapshot_job_v1", {
      p_trip_id: job.tripId,
      p_revision: job.revision,
      p_error: message,
    });
    return { ...job, status: "failed", error: message };
  }
}

Deno.serve(async (req) => {
  const id = requestId();
  if (req.method !== "POST") {
    return failure(
      id,
      405,
      "method_not_allowed",
      "Use POST for snapshot recomputation.",
    );
  }
  const configuredSecret = Deno.env.get("SNAPSHOT_WORKER_SECRET");
  const suppliedSecret = req.headers.get("x-tee-circle-worker-secret") ?? "";
  if (
    !configuredSecret ||
    !timingSafeStringEqual(configuredSecret, suppliedSecret)
  ) {
    return failure(
      id,
      401,
      "unauthorized",
      "A valid worker credential is required.",
    );
  }

  try {
    const admin = createAdminClient();
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

    let jobs: SnapshotJob[];
    if (body.tripId !== undefined || body.revision !== undefined) {
      const direct = { tripId: body.tripId, revision: body.revision };
      if (!isJob(direct)) {
        return failure(
          id,
          400,
          "invalid_request",
          "tripId and integer revision must be supplied together.",
        );
      }
      jobs = [direct];
    } else {
      const { data: leaseEnvelope, error: leaseError } = await admin.rpc(
        "lease_trip_snapshot_jobs_v1",
        { p_limit: 10 },
      );
      if (leaseError) throw new Error(`lease jobs RPC: ${leaseError.message}`);
      const leased = isObject(leaseEnvelope) &&
          isObject(leaseEnvelope.data) &&
          Array.isArray(leaseEnvelope.data.jobs)
        ? leaseEnvelope.data.jobs
        : null;
      if (!leased || !leased.every(isJob)) {
        throw new Error("invalid lease contract");
      }
      jobs = leased;
    }

    const results: Record<string, unknown>[] = [];
    for (const job of jobs) results.push(await processJob(admin, job));
    return success(id, {
      processed: results.length,
      results,
      engineVersion: SCORING_ENGINE_VERSION,
    });
  } catch (error) {
    console.error("recompute-trip-snapshot-v1 failed", {
      requestId: id,
      error,
    });
    return failure(
      id,
      500,
      "worker_failed",
      "Snapshot recomputation failed.",
      true,
    );
  }
});
