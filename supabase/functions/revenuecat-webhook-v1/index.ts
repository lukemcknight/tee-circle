import { createAdminClient } from "../_shared/admin.ts";
import {
  failure,
  isErrorEnvelope,
  isObject,
  requestId,
  success,
} from "../_shared/api-v1.ts";
import { timingSafeStringEqual } from "../_shared/crypto.ts";
import {
  parseRevenueCatWebhookPurchaseV1,
  type PendingPurchaseIntentV1,
  RevenueCatVerificationError,
  selectPurchaseIntentForWebhookV1,
  TRIP_UNLOCK_PRODUCT_ID,
} from "../_shared/revenuecat-platform-v1.ts";

function isIntent(value: unknown): value is PendingPurchaseIntentV1 {
  return isObject(value) &&
    typeof value.id === "string" &&
    typeof value.user_id === "string" &&
    typeof value.product_id === "string" &&
    typeof value.status === "string" &&
    typeof value.created_at === "string" &&
    typeof value.expires_at === "string" &&
    (value.cancelled_at === undefined || value.cancelled_at === null ||
      typeof value.cancelled_at === "string");
}

Deno.serve(async (req) => {
  const id = requestId();
  if (req.method !== "POST") {
    return failure(
      id,
      405,
      "method_not_allowed",
      "Use POST for RevenueCat webhooks.",
    );
  }

  const configuredAuthorization = Deno.env.get(
    "REVENUECAT_WEBHOOK_AUTHORIZATION",
  );
  const suppliedAuthorization = req.headers.get("authorization") ?? "";
  if (
    !configuredAuthorization ||
    !timingSafeStringEqual(configuredAuthorization, suppliedAuthorization)
  ) {
    return failure(
      id,
      401,
      "unauthorized",
      "A valid RevenueCat webhook credential is required.",
    );
  }

  try {
    const revenueCatAppId = Deno.env.get("REVENUECAT_APP_ID");
    if (!revenueCatAppId) {
      console.error("revenuecat-webhook-v1 is missing REVENUECAT_APP_ID", {
        requestId: id,
      });
      return failure(
        id,
        503,
        "webhook_unavailable",
        "Purchase reconciliation is temporarily unavailable.",
        true,
      );
    }
    const body: unknown = await req.json().catch(() => null);
    const event = parseRevenueCatWebhookPurchaseV1(body, {
      productId: TRIP_UNLOCK_PRODUCT_ID,
      revenueCatAppId,
    });
    if (!event) {
      return success(id, { handled: false, reason: "event_ignored" });
    }

    const admin = createAdminClient();
    const { data: replay, error: replayError } = await admin
      .from("trip_purchase_intents")
      .select(
        "id,user_id,trip_id,product_id,status,environment,revenuecat_transaction_id",
      )
      .eq("revenuecat_transaction_id", event.transactionId)
      .maybeSingle();
    if (replayError) {
      throw new Error(`purchase replay query: ${replayError.message}`);
    }
    if (isObject(replay)) {
      if (
        replay.user_id !== event.appUserId ||
        replay.product_id !== event.productId || replay.status !== "verified" ||
        replay.environment !== event.environment
      ) {
        return failure(
          id,
          409,
          "transaction_already_claimed",
          "That App Store transaction is already linked to another purchase.",
        );
      }
      return success(id, {
        handled: true,
        unlocked: true,
        idempotentReplay: true,
        tripId: replay.trip_id,
        eventId: event.eventId,
        environment: event.environment,
      });
    }

    const { data: rows, error: intentError } = await admin
      .from("trip_purchase_intents")
      .select(
        "id,user_id,product_id,status,created_at,expires_at,cancelled_at,revenuecat_transaction_id",
      )
      .eq("user_id", event.appUserId)
      .eq("product_id", event.productId)
      .in("status", ["pending", "expired", "cancelled"])
      .lte("created_at", event.purchasedAt)
      .gte("expires_at", event.purchasedAt)
      .order("created_at", { ascending: false })
      .limit(50);
    if (intentError) {
      throw new Error(`pending purchase query: ${intentError.message}`);
    }
    if (!Array.isArray(rows) || !rows.every(isIntent)) {
      throw new Error("invalid pending purchase intent contract");
    }
    const intent = selectPurchaseIntentForWebhookV1(rows, event);

    const { data: claim, error: claimError } = await admin.rpc(
      "verify_trip_purchase_v1",
      {
        p_purchase_intent_id: intent.id,
        p_product_id: event.productId,
        p_revenuecat_transaction_id: event.transactionId,
        p_environment: event.environment,
        p_purchased_at: event.purchasedAt,
        p_verified_at: new Date().toISOString(),
      },
    );
    if (claimError) {
      throw new Error(`purchase claim RPC: ${claimError.message}`);
    }
    if (isErrorEnvelope(claim)) {
      // A concurrent client claim may have won after the replay query.
      if (claim.error.code === "transaction_already_claimed") {
        const { data: concurrent } = await admin
          .from("trip_purchase_intents")
          .select("user_id,trip_id,product_id,status,environment")
          .eq("revenuecat_transaction_id", event.transactionId)
          .maybeSingle();
        if (
          isObject(concurrent) && concurrent.user_id === event.appUserId &&
          concurrent.product_id === event.productId &&
          concurrent.status === "verified" &&
          concurrent.environment === event.environment
        ) {
          return success(id, {
            handled: true,
            unlocked: true,
            idempotentReplay: true,
            tripId: concurrent.trip_id,
            eventId: event.eventId,
            environment: event.environment,
          });
        }
      }
      return failure(
        id,
        409,
        claim.error.code,
        claim.error.message,
        claim.error.retryable,
        claim.error.currentRevision,
      );
    }
    if (!isObject(claim) || !isObject(claim.data)) {
      throw new Error("invalid purchase claim RPC contract");
    }
    return success(id, {
      handled: true,
      ...claim.data,
      eventId: event.eventId,
      environment: event.environment,
    });
  } catch (error) {
    if (error instanceof RevenueCatVerificationError) {
      return failure(id, 409, error.code, error.message, error.retryable);
    }
    console.error("revenuecat-webhook-v1 failed", { requestId: id, error });
    return failure(
      id,
      500,
      "webhook_failed",
      "Purchase reconciliation failed.",
      true,
    );
  }
});
