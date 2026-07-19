import { createAdminClient } from "../_shared/admin.ts";
import {
  ActivityKitPayloadError,
  buildActivityKitPushV1,
  createApnsProviderTokenV1,
} from "../_shared/activitykit-apns-v1.ts";
import {
  failure,
  isErrorEnvelope,
  isObject,
  requestId,
  success,
} from "../_shared/api-v1.ts";
import { timingSafeStringEqual } from "../_shared/crypto.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface ActivityDelivery {
  subscriptionId: string;
  tripId: string;
  userId: string;
  activityId: string;
  pushToken: string;
  environment: "sandbox" | "production";
  expiresAt: string | null;
  revision: number;
  leaseId: string;
  activityTimestamp: number;
  payload: Record<string, unknown>;
  computedAt: string;
  viewerPlayerId: string;
}

function isDelivery(value: unknown): value is ActivityDelivery {
  return isObject(value) && typeof value.subscriptionId === "string" &&
    typeof value.tripId === "string" && typeof value.userId === "string" &&
    typeof value.activityId === "string" &&
    typeof value.pushToken === "string" &&
    (value.environment === "sandbox" || value.environment === "production") &&
    (value.expiresAt === null || typeof value.expiresAt === "string") &&
    typeof value.revision === "number" &&
    Number.isSafeInteger(value.revision) && value.revision >= 0 &&
    typeof value.leaseId === "string" && UUID_PATTERN.test(value.leaseId) &&
    typeof value.activityTimestamp === "number" &&
    Number.isSafeInteger(value.activityTimestamp) &&
    value.activityTimestamp > 0 &&
    isObject(value.payload) && typeof value.computedAt === "string" &&
    typeof value.viewerPlayerId === "string";
}

let cachedProviderToken:
  | { value: string; createdAt: number; identity: string }
  | null = null;

async function providerToken(
  teamId: string,
  keyId: string,
  privateKey: string,
): Promise<string> {
  const now = Date.now();
  const identity = `${teamId}:${keyId}`;
  if (
    cachedProviderToken && cachedProviderToken.identity === identity &&
    now - cachedProviderToken.createdAt < 45 * 60 * 1_000
  ) return cachedProviderToken.value;
  const value = await createApnsProviderTokenV1(
    teamId,
    keyId,
    privateKey,
    new Date(now),
  );
  cachedProviderToken = { value, createdAt: now, identity };
  return value;
}

async function sendActivityPush(
  delivery: ActivityDelivery,
  payload: unknown,
  priority: 5 | 10,
  isFinal: boolean,
  token: string,
  topic: string,
): Promise<{ status: number; reason: string | null }> {
  const host = delivery.environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const retentionSeconds = isFinal
    ? 24 * 60 * 60
    : priority === 10
    ? 60 * 60
    : 5 * 60;
  const expiration = Math.floor(Date.now() / 1_000) + retentionSeconds;
  const response = await fetch(
    `https://${host}/3/device/${encodeURIComponent(delivery.pushToken)}`,
    {
      method: "POST",
      headers: {
        Authorization: `bearer ${token}`,
        "Content-Type": "application/json",
        "apns-push-type": "liveactivity",
        "apns-topic": topic,
        "apns-priority": String(priority),
        "apns-expiration": String(expiration),
        // One collapse identity per subscription means APNs retains the newest
        // queued revision for an offline device.
        "apns-collapse-id": delivery.subscriptionId,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    },
  );
  if (response.ok) return { status: response.status, reason: null };
  const responseBody: unknown = await response.json().catch(() => null);
  return {
    status: response.status,
    reason: isObject(responseBody) && typeof responseBody.reason === "string"
      ? responseBody.reason
      : null,
  };
}

Deno.serve(async (req) => {
  const id = requestId();
  if (req.method !== "POST") {
    return failure(
      id,
      405,
      "method_not_allowed",
      "Use POST to dispatch Live Activity updates.",
    );
  }
  const configuredSecret = Deno.env.get("ACTIVITY_WORKER_SECRET");
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
  if (Deno.env.get("LIVE_ACTIVITY_PUSHES_ENABLED") !== "true") {
    return success(id, {
      enabled: false,
      processed: 0,
      message: "Live Activity pushes are disabled by the server kill switch.",
    });
  }

  try {
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
    const tripId = body.tripId;
    const revision = body.revision;
    const limit = body.limit ?? 50;
    if (
      (tripId !== undefined &&
        (typeof tripId !== "string" || !UUID_PATTERN.test(tripId))) ||
      (revision !== undefined &&
        (typeof revision !== "number" || !Number.isSafeInteger(revision) ||
          revision < 0)) ||
      ((tripId === undefined) !== (revision === undefined)) ||
      typeof limit !== "number" || !Number.isSafeInteger(limit) || limit < 1 ||
      limit > 100
    ) {
      return failure(
        id,
        400,
        "invalid_request",
        "Provide a valid tripId and revision together, with a limit from 1 to 100.",
      );
    }

    const admin = createAdminClient();
    const { data: flagEnvelope, error: flagError } = await admin.rpc(
      "get_runtime_flag_service_v1",
      { p_key: "live_activity_pushes_enabled" },
    );
    if (flagError || isErrorEnvelope(flagEnvelope)) {
      console.error("Live Activity database kill switch could not be read", {
        requestId: id,
        error: flagError?.message ??
          (isErrorEnvelope(flagEnvelope) ? flagEnvelope.error.code : null),
      });
      return failure(
        id,
        503,
        "kill_switch_unavailable",
        "Live Activity delivery is temporarily unavailable.",
        true,
      );
    }
    const flagData = isObject(flagEnvelope) && isObject(flagEnvelope.data)
      ? flagEnvelope.data
      : null;
    if (!flagData || typeof flagData.enabled !== "boolean") {
      return failure(
        id,
        503,
        "kill_switch_unavailable",
        "Live Activity delivery is temporarily unavailable.",
        true,
      );
    }
    if (!flagData.enabled) {
      return success(id, {
        enabled: false,
        processed: 0,
        message: "Live Activity pushes are disabled by the server kill switch.",
      });
    }

    const teamId = Deno.env.get("APNS_TEAM_ID");
    const keyId = Deno.env.get("APNS_KEY_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
    const topic = Deno.env.get("APNS_LIVE_ACTIVITY_TOPIC") ??
      "com.teecircle.app.push-type.liveactivity";
    if (
      !teamId || !keyId || !privateKey ||
      !topic.endsWith(".push-type.liveactivity")
    ) {
      console.error(
        "dispatch-live-activity-v1 is missing APNs server configuration",
        { requestId: id },
      );
      return failure(
        id,
        503,
        "apns_unavailable",
        "Live Activity delivery is temporarily unavailable.",
        true,
      );
    }

    const { data: leaseEnvelope, error: leaseError } = await admin.rpc(
      "lease_live_activity_deliveries_service_v1",
      {
        p_trip_id: typeof tripId === "string" ? tripId : null,
        p_requested_revision: typeof revision === "number" ? revision : null,
        p_limit: limit,
      },
    );
    if (leaseError || isErrorEnvelope(leaseEnvelope)) {
      throw new Error(
        `activity delivery lease: ${
          leaseError?.message ?? leaseEnvelope.error.code
        }`,
      );
    }
    const rows = isObject(leaseEnvelope) && isObject(leaseEnvelope.data) &&
        Array.isArray(leaseEnvelope.data.deliveries)
      ? leaseEnvelope.data.deliveries
      : null;
    if (!rows || !rows.every(isDelivery)) {
      throw new Error("invalid activity delivery lease contract");
    }
    const deliveries = rows as ActivityDelivery[];
    if (deliveries.length === 0) {
      return success(id, { enabled: true, processed: 0, results: [] });
    }

    const jwt = await providerToken(teamId, keyId, privateKey);
    const invalidTokenReasons = new Set([
      "BadDeviceToken",
      "DeviceTokenNotForTopic",
      "Unregistered",
    ]);
    const results: Array<Record<string, unknown>> = [];

    const finish = async (
      delivery: ActivityDelivery,
      outcome: "delivered" | "retry" | "terminal",
      isFinal: boolean,
    ) => {
      const { data, error } = await admin.rpc(
        "complete_live_activity_delivery_service_v1",
        {
          p_subscription_id: delivery.subscriptionId,
          p_revision: delivery.revision,
          p_lease_id: delivery.leaseId,
          p_outcome: outcome,
          p_is_final: isFinal,
        },
      );
      if (error || isErrorEnvelope(data)) {
        throw new Error(
          `activity delivery completion: ${error?.message ?? data.error.code}`,
        );
      }
    };

    for (const delivery of deliveries) {
      try {
        const activityDate = new Date(delivery.activityTimestamp * 1_000);
        if (!Number.isFinite(activityDate.getTime())) {
          throw new ActivityKitPayloadError(
            "snapshot_timestamp_invalid",
            "Canonical snapshot timestamp is invalid.",
          );
        }
        // The lease allocates a strictly increasing timestamp per
        // subscription, independent of Edge request arrival order.
        const push = buildActivityKitPushV1(
          delivery.payload,
          delivery.viewerPlayerId,
          activityDate,
        );
        const response = await sendActivityPush(
          delivery,
          push.payload,
          push.priority,
          push.isFinal,
          jwt,
          topic,
        );
        if (response.status === 200) {
          await finish(delivery, "delivered", push.isFinal);
          results.push({
            activityId: delivery.activityId,
            status: push.isFinal ? "ended" : "updated",
            revision: delivery.revision,
            priority: push.priority,
          });
          continue;
        }

        const terminal = response.status === 410 ||
          (response.reason !== null &&
            invalidTokenReasons.has(response.reason));
        await finish(delivery, terminal ? "terminal" : "retry", false);
        results.push({
          activityId: delivery.activityId,
          status: terminal ? "token_invalid" : "delivery_failed",
          apnsStatus: response.status,
          retryable: !terminal,
        });
      } catch (error) {
        await finish(delivery, "retry", false).catch((completionError) => {
          console.error("Live Activity lease release failed", {
            requestId: id,
            activityId: delivery.activityId,
            completionError,
          });
        });
        const code = error instanceof ActivityKitPayloadError
          ? error.code
          : "delivery_failed";
        console.error("Live Activity delivery failed", {
          requestId: id,
          activityId: delivery.activityId,
          code,
        });
        results.push({
          activityId: delivery.activityId,
          status: "delivery_failed",
          code,
          retryable: true,
        });
      }
    }
    return success(id, {
      enabled: true,
      processed: deliveries.length,
      results,
    });
  } catch (error) {
    console.error("dispatch-live-activity-v1 failed", { requestId: id, error });
    return failure(
      id,
      500,
      "activity_dispatch_failed",
      "Live Activity delivery failed.",
      true,
    );
  }
});
