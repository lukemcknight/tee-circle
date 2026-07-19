import { isErrorEnvelope, isObject } from "./api-v1.ts";

export interface ActivityDispatchResultV1 {
  status: "dispatched" | "disabled" | "deferred";
  processed: number;
  code?: string;
}

/** Activity delivery is downstream of the committed score/snapshot. Failures
 * are returned as deferred so clients never retry an already accepted score
 * under a new idempotency key. */
export async function dispatchLiveActivityUpdateV1(
  tripId: string,
  revision: number,
): Promise<ActivityDispatchResultV1> {
  const baseUrl = Deno.env.get("SUPABASE_URL");
  const workerSecret = Deno.env.get("ACTIVITY_WORKER_SECRET");
  if (!baseUrl || !workerSecret) {
    return { status: "deferred", processed: 0, code: "not_configured" };
  }
  try {
    const result = await fetch(
      `${baseUrl.replace(/\/$/, "")}/functions/v1/dispatch-live-activity-v1`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-tee-circle-worker-secret": workerSecret,
        },
        body: JSON.stringify({ schemaVersion: 1, tripId, revision }),
        signal: AbortSignal.timeout(15_000),
      },
    );
    const envelope: unknown = await result.json().catch(() => null);
    if (!result.ok || isErrorEnvelope(envelope)) {
      return {
        status: "deferred",
        processed: 0,
        code: isErrorEnvelope(envelope)
          ? envelope.error.code
          : `http_${result.status}`,
      };
    }
    const data = isObject(envelope) && isObject(envelope.data)
      ? envelope.data
      : null;
    if (!data) {
      return { status: "deferred", processed: 0, code: "invalid_response" };
    }
    const processed = typeof data.processed === "number" &&
        Number.isSafeInteger(data.processed)
      ? data.processed
      : 0;
    return {
      status: data.enabled === false ? "disabled" : "dispatched",
      processed,
    };
  } catch (error) {
    console.error("Live Activity dispatch deferred", {
      tripId,
      revision,
      error,
    });
    return { status: "deferred", processed: 0, code: "dispatch_failed" };
  }
}
