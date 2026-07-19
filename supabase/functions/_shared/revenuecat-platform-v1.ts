import { isObject } from "./api-v1.ts";

export const TRIP_UNLOCK_PRODUCT_ID =
  "com.teecircle.app.trip_unlock_2999" as const;

export class RevenueCatVerificationError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly retryable = false,
  ) {
    super(message);
    this.name = "RevenueCatVerificationError";
  }
}

export interface VerifiedRevenueCatPurchaseV1 {
  transactionId: string;
  productId: typeof TRIP_UNLOCK_PRODUCT_ID;
  appUserId: string;
  purchaseResourceId: string;
  purchasedAt: string;
  environment: "sandbox" | "production";
}

export interface RevenueCatWebhookPurchaseV1 {
  eventId: string;
  transactionId: string;
  productId: typeof TRIP_UNLOCK_PRODUCT_ID;
  appUserId: string;
  purchasedAt: string;
  environment: "sandbox" | "production";
}

export interface PendingPurchaseIntentV1 {
  id: string;
  user_id: string;
  product_id: string;
  status: string;
  created_at: string;
  expires_at: string;
  cancelled_at?: string | null;
  revenuecat_transaction_id?: string | null;
}

function findPurchaseCandidate(
  purchaseSearch: unknown,
  transactionId: string,
): Record<string, unknown> {
  if (!isObject(purchaseSearch) || !Array.isArray(purchaseSearch.items)) {
    throw new RevenueCatVerificationError(
      "revenuecat_contract_invalid",
      "RevenueCat returned an invalid purchase response.",
      true,
    );
  }
  const matches = purchaseSearch.items.filter((candidate) =>
    isObject(candidate) &&
    String(candidate.store_purchase_identifier) === transactionId
  );
  if (matches.length === 0) {
    throw new RevenueCatVerificationError(
      "purchase_not_found",
      "RevenueCat has not confirmed this App Store transaction yet.",
      true,
    );
  }
  if (matches.length !== 1) {
    throw new RevenueCatVerificationError(
      "purchase_ambiguous",
      "RevenueCat returned more than one matching purchase.",
    );
  }
  return matches[0] as Record<string, unknown>;
}

export function revenueCatProductResourceIdV1(
  purchaseSearch: unknown,
  transactionId: string,
): string {
  return requiredString(
    findPurchaseCandidate(purchaseSearch, transactionId).product_id,
    "purchase product id",
  );
}

function requiredString(
  value: unknown,
  field: string,
  min = 1,
  max = 255,
): string {
  if (
    typeof value !== "string" || value.length < min || value.length > max
  ) {
    throw new RevenueCatVerificationError(
      "revenuecat_contract_invalid",
      `RevenueCat returned an invalid ${field}.`,
      true,
    );
  }
  return value;
}

function normalizedEnvironment(value: unknown): "sandbox" | "production" {
  if (typeof value !== "string") {
    throw new RevenueCatVerificationError(
      "revenuecat_contract_invalid",
      "RevenueCat did not return a purchase environment.",
      true,
    );
  }
  switch (value.toLowerCase()) {
    case "sandbox":
      return "sandbox";
    case "production":
      return "production";
    default:
      throw new RevenueCatVerificationError(
        "purchase_environment_invalid",
        "RevenueCat returned an unsupported purchase environment.",
      );
  }
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function purchasedAt(value: unknown, now: Date): string {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new RevenueCatVerificationError(
      "revenuecat_contract_invalid",
      "RevenueCat returned an invalid purchase timestamp.",
      true,
    );
  }
  const date = new Date(value);
  if (
    !Number.isFinite(date.getTime()) || date.getTime() > now.getTime() + 300_000
  ) {
    throw new RevenueCatVerificationError(
      "purchase_timestamp_invalid",
      "The purchase timestamp is not valid.",
    );
  }
  return date.toISOString();
}

/**
 * Verifies the two RevenueCat v2 resources needed to bind an App Store
 * transaction to a TeeCircle user. The purchase search proves the transaction
 * and owner; the product resource proves the store product and RevenueCat app.
 */
export function verifyRevenueCatPurchaseV1(
  purchaseSearch: unknown,
  productResource: unknown,
  expected: {
    transactionId: string;
    productId: typeof TRIP_UNLOCK_PRODUCT_ID;
    appUserId: string;
    revenueCatAppId: string;
    now?: Date;
  },
): VerifiedRevenueCatPurchaseV1 {
  const purchase = findPurchaseCandidate(
    purchaseSearch,
    expected.transactionId,
  );
  const purchaseOwner = requiredString(
    purchase.customer_id,
    "customer id",
    1,
    1_500,
  );
  if (purchaseOwner !== expected.appUserId) {
    throw new RevenueCatVerificationError(
      "purchase_user_mismatch",
      "The App Store transaction belongs to another TeeCircle account.",
    );
  }
  if (purchase.store !== "app_store") {
    throw new RevenueCatVerificationError(
      "purchase_store_mismatch",
      "The transaction is not an Apple App Store purchase.",
    );
  }
  if (purchase.status !== "owned" || Number(purchase.quantity ?? 0) < 1) {
    throw new RevenueCatVerificationError(
      "purchase_not_owned",
      "RevenueCat does not report this transaction as owned.",
    );
  }

  if (!isObject(productResource)) {
    throw new RevenueCatVerificationError(
      "revenuecat_contract_invalid",
      "RevenueCat returned an invalid product response.",
      true,
    );
  }
  const purchaseProductResourceId = requiredString(
    purchase.product_id,
    "purchase product id",
  );
  if (productResource.id !== purchaseProductResourceId) {
    throw new RevenueCatVerificationError(
      "purchase_product_mismatch",
      "The RevenueCat product does not match this transaction.",
    );
  }
  if (
    productResource.store_identifier !== expected.productId ||
    productResource.app_id !== expected.revenueCatAppId ||
    !isObject(productResource.one_time) ||
    productResource.one_time.is_consumable !== true
  ) {
    throw new RevenueCatVerificationError(
      "purchase_product_mismatch",
      "The transaction is not the TeeCircle trip unlock product.",
    );
  }

  return {
    transactionId: expected.transactionId,
    productId: expected.productId,
    appUserId: expected.appUserId,
    purchaseResourceId: requiredString(purchase.id, "purchase resource id"),
    purchasedAt: purchasedAt(purchase.purchased_at, expected.now ?? new Date()),
    environment: normalizedEnvironment(purchase.environment),
  };
}

/** Parse only the webhook event TeeCircle acts on; all other event types are acknowledged. */
export function parseRevenueCatWebhookPurchaseV1(
  body: unknown,
  expected: {
    productId: typeof TRIP_UNLOCK_PRODUCT_ID;
    revenueCatAppId: string;
    now?: Date;
  },
): RevenueCatWebhookPurchaseV1 | null {
  if (!isObject(body) || !isObject(body.event)) {
    throw new RevenueCatVerificationError(
      "invalid_webhook",
      "RevenueCat webhook payload is invalid.",
    );
  }
  const event = body.event;
  if (event.type !== "NON_RENEWING_PURCHASE") return null;
  if (
    event.product_id !== expected.productId ||
    event.app_id !== expected.revenueCatAppId ||
    event.store !== "APP_STORE"
  ) {
    throw new RevenueCatVerificationError(
      "webhook_purchase_mismatch",
      "The webhook is not for the TeeCircle App Store trip unlock.",
    );
  }
  const appUserId = requiredString(event.app_user_id, "app user id", 1, 1_500);
  if (!isUuid(appUserId)) {
    throw new RevenueCatVerificationError(
      "webhook_user_invalid",
      "The webhook App User ID is not a Supabase user UUID.",
    );
  }
  return {
    eventId: requiredString(event.id, "event id"),
    transactionId: requiredString(event.transaction_id, "transaction id"),
    productId: expected.productId,
    appUserId,
    purchasedAt: purchasedAt(event.purchased_at_ms, expected.now ?? new Date()),
    environment: normalizedEnvironment(event.environment),
  };
}

/**
 * Correlates a webhook to the most recently opened intent that existed during
 * the verified StoreKit purchase. Only one intent may be pending per user and
 * product, while cancelled/expired rows remain for crash recovery.
 */
export function selectPurchaseIntentForWebhookV1(
  intents: PendingPurchaseIntentV1[],
  event: RevenueCatWebhookPurchaseV1,
): PendingPurchaseIntentV1 {
  const purchased = new Date(event.purchasedAt).getTime();
  const valid = intents.filter((intent) =>
    intent.user_id === event.appUserId &&
    intent.product_id === event.productId &&
    ["pending", "expired", "cancelled"].includes(intent.status) &&
    new Date(intent.created_at).getTime() <= purchased &&
    new Date(intent.expires_at).getTime() >= purchased &&
    (intent.status !== "cancelled" || intent.cancelled_at === null ||
      intent.cancelled_at === undefined ||
      new Date(intent.cancelled_at).getTime() >= purchased)
  );
  if (valid.length === 0) {
    throw new RevenueCatVerificationError(
      "purchase_intent_not_found",
      "No trip purchase intent matches this transaction.",
      true,
    );
  }
  if (valid.length > 1) {
    throw new RevenueCatVerificationError(
      "purchase_intent_ambiguous",
      "More than one trip purchase intent matches this transaction.",
      false,
    );
  }
  return [...valid].sort((left, right) => {
    const time = new Date(right.created_at).getTime() -
      new Date(left.created_at).getTime();
    return time !== 0 ? time : right.id.localeCompare(left.id);
  })[0];
}
