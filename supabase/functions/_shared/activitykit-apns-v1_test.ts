import {
  ACTIVITYKIT_CONTENT_STATE_LIMIT,
  ActivityKitPayloadError,
  buildActivityKitPushV1,
  createApnsProviderTokenV1,
} from "./activitykit-apns-v1.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertLess(actual: number, maximum: number): void {
  if (!(actual < maximum)) {
    throw new Error(`Expected ${actual} to be less than ${maximum}`);
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

async function assertRejects<T extends Error>(
  operation: () => Promise<unknown>,
  errorType: new (...args: never[]) => T,
): Promise<T> {
  try {
    await operation();
  } catch (error) {
    if (error instanceof errorType) return error;
    throw error;
  }
  throw new Error("Expected operation to reject");
}

function snapshot(overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    tripId: "trip-pinehurst-2026",
    revision: 42,
    status: "live",
    primaryFormat: "stableford",
    currentRound: {
      publicId: "round-1",
      name: "Pinehurst No. 2",
      throughHole: 12,
    },
    boards: [{
      format: "stableford",
      scoring: "net",
      standings: [
        { playerId: "seat-sean", displayName: "Sean", rank: 1, value: 28 },
        { playerId: "seat-luke", displayName: "Luke", rank: 2, value: 26 },
      ],
    }],
    moment: { kind: "lead_change", summary: "Sean took the lead through 12" },
    generatedAt: "2026-07-13T18:42:10.125Z",
    ...overrides,
  };
}

Deno.test("ActivityKit payload maps canonical leader and per-user rank", () => {
  const push = buildActivityKitPushV1(
    snapshot(),
    "seat-luke",
    new Date("2026-07-13T18:43:00Z"),
  );
  assertEquals(push.priority, 10);
  assertEquals(push.isFinal, false);
  assertEquals(push.contentState.leaderName, "Sean");
  assertEquals(push.contentState.viewerRank, 2);
  assertEquals(push.payload.aps.event, "update");
  assertLess(
    new TextEncoder().encode(JSON.stringify(push.contentState)).byteLength,
    ACTIVITYKIT_CONTENT_STATE_LIMIT,
  );
});

Deno.test("ActivityKit ends completed trips and routine updates stay low priority", () => {
  const routine = buildActivityKitPushV1(snapshot({ moment: null }), null);
  assertEquals(routine.priority, 5);
  assertEquals("alert" in routine.payload.aps, false);

  const final = buildActivityKitPushV1(
    snapshot({ status: "completed", moment: null }),
    null,
  );
  assertEquals(final.priority, 10);
  assertEquals(final.payload.aps.event, "end");
  assertEquals(typeof final.payload.aps["dismissal-date"], "number");

  const archived = buildActivityKitPushV1(
    snapshot({ status: "archived", moment: null }),
    null,
  );
  assertEquals(archived.priority, 10);
  assertEquals(archived.isFinal, true);
  assertEquals(archived.payload.aps.event, "end");
});

Deno.test("ActivityKit reads skins carry from the canonical skins board", () => {
  const push = buildActivityKitPushV1(
    snapshot({
      primaryFormat: "stableford",
      boards: [
        { format: "stableford", standings: [] },
        { format: "skins", skinsCarry: 4, standings: [] },
      ],
    }),
    null,
  );
  assertEquals(push.contentState.skinsCarry, 4);
});

Deno.test("ActivityKit rejects content state over Apple's four kilobyte limit", () => {
  const standings = Array.from({ length: 2 }, (_, index) => ({
    playerId: `seat-${index}`,
    displayName: "x".repeat(5_000),
    rank: index + 1,
    value: 1,
  }));
  // Names are bounded before broadcast, keeping a hostile snapshot safely small.
  const bounded = buildActivityKitPushV1(
    snapshot({
      boards: [{ format: "stableford", standings }],
    }),
    null,
  );
  assertLess(
    new TextEncoder().encode(JSON.stringify(bounded.contentState)).byteLength,
    ACTIVITYKIT_CONTENT_STATE_LIMIT,
  );

  const error = assertThrows(
    () =>
      buildActivityKitPushV1(snapshot({ revision: Number.MAX_VALUE }), null),
    ActivityKitPayloadError,
  );
  assertEquals(error.code, "invalid_snapshot");
});

Deno.test("APNs provider token is a signed ES256 JWT", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const exported = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  let binary = "";
  for (const byte of exported) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(binary)
  }\n-----END PRIVATE KEY-----`;
  const token = await createApnsProviderTokenV1(
    "9974PM5L6M",
    "KEY1234567",
    pem,
    new Date("2026-07-13T18:42:00Z"),
  );
  const segments = token.split(".");
  assertEquals(segments.length, 3);

  const decode = (value: string) => {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
      "=".repeat((4 - value.length % 4) % 4);
    return Uint8Array.from(
      atob(padded),
      (character) => character.charCodeAt(0),
    );
  };
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    keys.publicKey,
    decode(segments[2]),
    new TextEncoder().encode(`${segments[0]}.${segments[1]}`),
  );
  assertEquals(valid, true);

  await assertRejects(
    () => createApnsProviderTokenV1("", "", ""),
    ActivityKitPayloadError,
  );
});
