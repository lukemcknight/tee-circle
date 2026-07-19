import {
  parseRevenueCatWebhookPurchaseV1,
  RevenueCatVerificationError,
  selectPurchaseIntentForWebhookV1,
  TRIP_UNLOCK_PRODUCT_ID,
  verifyRevenueCatPurchaseV1,
} from "./revenuecat-platform-v1.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertThrows<T extends Error>(
  operation: () => unknown,
  errorType: new (...args: never[]) => T,
): T {
  try {
    operation();
  } catch (error) {
    if (error instanceof errorType) return error;
    throw error;
  }
  throw new Error("Expected operation to throw");
}

const userId = "11111111-1111-4111-8111-111111111111";
const now = new Date("2026-07-13T18:45:00Z");

function purchaseSearch(overrides: Record<string, unknown> = {}) {
  return {
    object: "list",
    items: [{
      object: "purchase",
      id: "purch_tee_circle",
      customer_id: userId,
      original_customer_id: userId,
      product_id: "prod_tee_circle",
      purchased_at: Date.parse("2026-07-13T18:42:00Z"),
      quantity: 1,
      status: "owned",
      environment: "sandbox",
      store: "app_store",
      store_purchase_identifier: "200000000000001",
      ...overrides,
    }],
  };
}

const product = {
  object: "product",
  id: "prod_tee_circle",
  app_id: "app_tee_circle",
  store_identifier: TRIP_UNLOCK_PRODUCT_ID,
  one_time: { is_consumable: true },
};

Deno.test("RevenueCat verifier binds transaction, product, app, and user", () => {
  const verified = verifyRevenueCatPurchaseV1(purchaseSearch(), product, {
    transactionId: "200000000000001",
    productId: TRIP_UNLOCK_PRODUCT_ID,
    appUserId: userId,
    revenueCatAppId: "app_tee_circle",
    now,
  });
  assertEquals(verified.productId, TRIP_UNLOCK_PRODUCT_ID);
  assertEquals(verified.appUserId, userId);
  assertEquals(verified.environment, "sandbox");
});

Deno.test("RevenueCat verifier rejects a transaction owned by another user", () => {
  const error = assertThrows(
    () =>
      verifyRevenueCatPurchaseV1(
        purchaseSearch({ customer_id: "22222222-2222-4222-8222-222222222222" }),
        product,
        {
          transactionId: "200000000000001",
          productId: TRIP_UNLOCK_PRODUCT_ID,
          appUserId: userId,
          revenueCatAppId: "app_tee_circle",
          now,
        },
      ),
    RevenueCatVerificationError,
  );
  assertEquals(error.code, "purchase_user_mismatch");
});

Deno.test("RevenueCat verifier rejects a lookalike store product", () => {
  const error = assertThrows(
    () =>
      verifyRevenueCatPurchaseV1(
        purchaseSearch(),
        { ...product, store_identifier: `${TRIP_UNLOCK_PRODUCT_ID}.fake` },
        {
          transactionId: "200000000000001",
          productId: TRIP_UNLOCK_PRODUCT_ID,
          appUserId: userId,
          revenueCatAppId: "app_tee_circle",
          now,
        },
      ),
    RevenueCatVerificationError,
  );
  assertEquals(error.code, "purchase_product_mismatch");
});

Deno.test("RevenueCat webhook parser accepts only the non-renewing Apple product", () => {
  const event = parseRevenueCatWebhookPurchaseV1({
    api_version: "1.0",
    event: {
      id: "event-1",
      type: "NON_RENEWING_PURCHASE",
      product_id: TRIP_UNLOCK_PRODUCT_ID,
      app_id: "app_tee_circle",
      transaction_id: "200000000000001",
      app_user_id: userId,
      purchased_at_ms: Date.parse("2026-07-13T18:42:00Z"),
      environment: "SANDBOX",
      store: "APP_STORE",
    },
  }, {
    productId: TRIP_UNLOCK_PRODUCT_ID,
    revenueCatAppId: "app_tee_circle",
    now,
  });
  assertEquals(event?.transactionId, "200000000000001");
  assertEquals(event?.environment, "sandbox");

  assertEquals(
    parseRevenueCatWebhookPurchaseV1({
      event: { type: "INITIAL_PURCHASE" },
    }, {
      productId: TRIP_UNLOCK_PRODUCT_ID,
      revenueCatAppId: "app_tee_circle",
      now,
    }),
    null,
  );
});

Deno.test("webhook reconciliation chooses the latest intent open at purchase time", () => {
  const event = {
    eventId: "event-1",
    transactionId: "200000000000001",
    productId: TRIP_UNLOCK_PRODUCT_ID,
    appUserId: userId,
    purchasedAt: "2026-07-13T18:42:00.000Z",
    environment: "sandbox" as const,
  };
  const makeIntent = (id: string, minute: string) => ({
    id,
    user_id: userId,
    product_id: TRIP_UNLOCK_PRODUCT_ID,
    status: "pending",
    created_at: `2026-07-13T18:${minute}:00.000Z`,
    expires_at: "2026-07-14T18:00:00.000Z",
  });
  assertEquals(
    selectPurchaseIntentForWebhookV1([makeIntent("intent-1", "40")], event).id,
    "intent-1",
  );
  assertEquals(
    selectPurchaseIntentForWebhookV1([
      {
        ...makeIntent("intent-1", "40"),
        status: "cancelled",
        cancelled_at: "2026-07-13T18:40:30.000Z",
      },
      makeIntent("intent-2", "41"),
    ], event).id,
    "intent-2",
  );
});

Deno.test("webhook reconciliation repairs an expired intent bought in-window", () => {
  const event = {
    eventId: "event-delayed",
    transactionId: "200000000000002",
    productId: TRIP_UNLOCK_PRODUCT_ID,
    appUserId: userId,
    purchasedAt: "2026-07-13T18:42:00.000Z",
    environment: "production" as const,
  };
  const intent = {
    id: "intent-expired",
    user_id: userId,
    product_id: TRIP_UNLOCK_PRODUCT_ID,
    status: "expired",
    created_at: "2026-07-13T18:40:00.000Z",
    expires_at: "2026-07-14T18:40:00.000Z",
  };
  assertEquals(selectPurchaseIntentForWebhookV1([intent], event).id, intent.id);
});

Deno.test("webhook reconciliation excludes intents opened after purchase", () => {
  const event = {
    eventId: "event-race",
    transactionId: "200000000000003",
    productId: TRIP_UNLOCK_PRODUCT_ID,
    appUserId: userId,
    purchasedAt: "2026-07-13T18:42:00.000Z",
    environment: "production" as const,
  };
  const oldIntent = {
    id: "intent-a",
    user_id: userId,
    product_id: TRIP_UNLOCK_PRODUCT_ID,
    status: "cancelled",
    created_at: "2026-07-13T18:40:00.000Z",
    cancelled_at: "2026-07-13T18:42:05.000Z",
    expires_at: "2026-07-14T18:40:00.000Z",
  };
  const laterIntent = {
    id: "intent-b",
    user_id: userId,
    product_id: TRIP_UNLOCK_PRODUCT_ID,
    status: "pending",
    created_at: "2026-07-13T18:42:01.000Z",
    expires_at: "2026-07-14T18:42:01.000Z",
  };
  assertEquals(
    selectPurchaseIntentForWebhookV1([oldIntent, laterIntent], event).id,
    oldIntent.id,
  );
});

Deno.test("webhook reconciliation rejects overlapping historical intents", () => {
  const event = {
    eventId: "event-ambiguous",
    transactionId: "200000000000004",
    productId: TRIP_UNLOCK_PRODUCT_ID,
    appUserId: userId,
    purchasedAt: "2026-07-13T18:42:00.000Z",
    environment: "sandbox" as const,
  };
  const intent = (id: string, createdAt: string) => ({
    id,
    user_id: userId,
    product_id: TRIP_UNLOCK_PRODUCT_ID,
    status: "expired",
    created_at: createdAt,
    expires_at: "2026-07-14T18:42:00.000Z",
  });
  const error = assertThrows(
    () =>
      selectPurchaseIntentForWebhookV1([
        intent("intent-a", "2026-07-13T18:40:00.000Z"),
        intent("intent-b", "2026-07-13T18:41:00.000Z"),
      ], event),
    RevenueCatVerificationError,
  );
  assertEquals(error.code, "purchase_intent_ambiguous");
});
