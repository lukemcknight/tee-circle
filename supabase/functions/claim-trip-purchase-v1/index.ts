import { createAdminClient } from "../_shared/admin.ts";
import {
  failure,
  isErrorEnvelope,
  isObject,
  requestId,
  success,
} from "../_shared/api-v1.ts";
import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions } from "../_shared/cors.ts";
import {
  revenueCatProductResourceIdV1,
  RevenueCatVerificationError,
  TRIP_UNLOCK_PRODUCT_ID,
  verifyRevenueCatPurchaseV1,
} from "../_shared/revenuecat-platform-v1.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TRANSACTION_PATTERN = /^[A-Za-z0-9._:-]{1,255}$/;

class RevenueCatUpstreamError extends Error {
  constructor(readonly status: number, readonly retryable: boolean) {
    super("RevenueCat request failed");
    this.name = "RevenueCatUpstreamError";
  }
}

async function revenueCatGet(
  path: string,
  secretKey: string,
): Promise<unknown> {
  const response = await fetch(`https://api.revenuecat.com/v2${path}`, {
    headers: {
      Authorization: `Bearer ${secretKey}`,
      Accept: "application/json",
    },
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) {
    throw new RevenueCatUpstreamError(
      response.status,
      response.status === 404 || response.status === 408 ||
        response.status === 423 || response.status === 429 ||
        response.status >= 500,
    );
  }
  try {
    return await response.json();
  } catch {
    throw new RevenueCatUpstreamError(502, true);
  }
}

function sqlFailureStatus(code: string): number {
  switch (code) {
    case "purchase_intent_not_found":
      return 404;
    case "purchase_intent_expired":
    case "purchase_mismatch":
    case "purchase_intent_already_claimed":
    case "transaction_already_claimed":
      return 409;
    default:
      return 400;
  }
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
      "Use POST to claim a purchase.",
    );
  }

  try {
    const user = await requireUser(req);
    const body: unknown = await req.json().catch(() => null);
    if (
      !isObject(body) || body.schemaVersion !== 1 ||
      typeof body.purchaseIntentId !== "string" ||
      !UUID_PATTERN.test(body.purchaseIntentId) ||
      typeof body.transactionId !== "string" ||
      !TRANSACTION_PATTERN.test(body.transactionId) ||
      body.productId !== TRIP_UNLOCK_PRODUCT_ID
    ) {
      return failure(
        id,
        400,
        "invalid_request",
        "A valid purchase intent, transaction, and TeeCircle product are required.",
      );
    }

    const secretKey = Deno.env.get("REVENUECAT_V2_SECRET_API_KEY");
    const projectId = Deno.env.get("REVENUECAT_PROJECT_ID");
    const revenueCatAppId = Deno.env.get("REVENUECAT_APP_ID");
    if (!secretKey || !projectId || !revenueCatAppId) {
      console.error(
        "claim-trip-purchase-v1 is missing RevenueCat server configuration",
        {
          requestId: id,
        },
      );
      return failure(
        id,
        503,
        "purchase_verification_unavailable",
        "Purchase verification is temporarily unavailable.",
        true,
      );
    }

    const admin = createAdminClient();
    const { data: intent, error: intentError } = await admin
      .from("trip_purchase_intents")
      .select(
        "id,user_id,product_id,status,expires_at,revenuecat_transaction_id",
      )
      .eq("id", body.purchaseIntentId)
      .maybeSingle();
    if (intentError) {
      throw new Error(`purchase intent query: ${intentError.message}`);
    }
    if (!isObject(intent)) {
      return failure(
        id,
        404,
        "purchase_intent_not_found",
        "Purchase intent not found.",
      );
    }
    if (intent.user_id !== user.id) {
      return failure(
        id,
        403,
        "forbidden",
        "This purchase intent belongs to another TeeCircle account.",
      );
    }
    if (intent.product_id !== TRIP_UNLOCK_PRODUCT_ID) {
      return failure(
        id,
        409,
        "purchase_mismatch",
        "The purchase intent does not match the trip unlock product.",
      );
    }

    const encodedProject = encodeURIComponent(projectId);
    const encodedTransaction = encodeURIComponent(body.transactionId);
    const purchaseSearch = await revenueCatGet(
      `/projects/${encodedProject}/purchases?store_purchase_identifier=${encodedTransaction}`,
      secretKey,
    );
    const productResourceId = revenueCatProductResourceIdV1(
      purchaseSearch,
      body.transactionId,
    );
    const productResource = await revenueCatGet(
      `/projects/${encodedProject}/products/${
        encodeURIComponent(productResourceId)
      }`,
      secretKey,
    );
    const verified = verifyRevenueCatPurchaseV1(
      purchaseSearch,
      productResource,
      {
        transactionId: body.transactionId,
        productId: TRIP_UNLOCK_PRODUCT_ID,
        appUserId: user.id,
        revenueCatAppId,
      },
    );

    const { data: claim, error: claimError } = await admin.rpc(
      "verify_trip_purchase_v1",
      {
        p_purchase_intent_id: body.purchaseIntentId,
        p_product_id: verified.productId,
        p_revenuecat_transaction_id: verified.transactionId,
        p_environment: verified.environment,
        p_purchased_at: verified.purchasedAt,
        p_verified_at: new Date().toISOString(),
      },
    );
    if (claimError) {
      throw new Error(`purchase claim RPC: ${claimError.message}`);
    }
    if (isErrorEnvelope(claim)) {
      return failure(
        id,
        sqlFailureStatus(claim.error.code),
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
      ...claim.data,
      productId: verified.productId,
      environment: verified.environment,
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return failure(id, 401, "unauthenticated", "Sign in is required.");
    }
    if (error instanceof RevenueCatVerificationError) {
      const status = error.code === "purchase_not_found" ? 404 : 409;
      return failure(id, status, error.code, error.message, error.retryable);
    }
    if (error instanceof RevenueCatUpstreamError) {
      console.error("RevenueCat purchase lookup failed", {
        requestId: id,
        upstreamStatus: error.status,
      });
      return failure(
        id,
        503,
        "purchase_verification_unavailable",
        "RevenueCat could not confirm the purchase yet.",
        error.retryable,
      );
    }
    console.error("claim-trip-purchase-v1 failed", { requestId: id, error });
    return failure(
      id,
      500,
      "internal_error",
      "Purchase verification failed.",
      true,
    );
  }
});
