import { isObject } from "./api-v1.ts";

const APPLE_REFERENCE_DATE_UNIX_SECONDS = 978_307_200;
export const ACTIVITYKIT_CONTENT_STATE_LIMIT = 4_096;

export class ActivityKitPayloadError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "ActivityKitPayloadError";
  }
}

interface StandingV1 {
  playerId: string;
  displayName: string;
  rank: number;
  value: number;
}

export interface TeeCircleActivityContentStateV1 {
  revision: number;
  status: string;
  roundName: string | null;
  throughHole: number;
  leaderName: string | null;
  leaderValue: number | null;
  viewerRank: number | null;
  viewerValue: number | null;
  skinsCarry: number | null;
  /** Swift Codable's default Date representation: seconds since 2001-01-01. */
  updatedAt: number;
}

export interface ActivityKitPushV1 {
  payload: {
    aps: Record<string, unknown>;
  };
  contentState: TeeCircleActivityContentStateV1;
  priority: 5 | 10;
  isFinal: boolean;
}

function byteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function safeInteger(value: unknown, field: string, minimum = 0): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value < minimum
  ) {
    throw new ActivityKitPayloadError(
      "invalid_snapshot",
      `Snapshot ${field} is invalid.`,
    );
  }
  return value;
}

function parseStanding(value: unknown): StandingV1 | null {
  if (
    !isObject(value) || typeof value.playerId !== "string" ||
    typeof value.displayName !== "string" ||
    typeof value.rank !== "number" || !Number.isSafeInteger(value.rank) ||
    typeof value.value !== "number" || !Number.isSafeInteger(value.value)
  ) return null;
  return {
    playerId: value.playerId,
    displayName: value.displayName,
    rank: value.rank,
    value: value.value,
  };
}

function truncate(value: string, maximum: number): string {
  return Array.from(value).slice(0, maximum).join("");
}

export function activityKitPriorityV1(snapshot: unknown): 5 | 10 {
  if (!isObject(snapshot)) return 5;
  if (snapshot.status === "completed" || snapshot.status === "archived") {
    return 10;
  }
  const immediateKinds = new Set([
    "lead_change",
    "skin_won",
    "round_started",
    "round_completed",
    "trip_completed",
  ]);
  return isObject(snapshot.moment) &&
      typeof snapshot.moment.kind === "string" &&
      immediateKinds.has(snapshot.moment.kind)
    ? 10
    : 5;
}

export function buildActivityKitPushV1(
  snapshot: unknown,
  viewerPlayerId: string | null,
  now = new Date(),
): ActivityKitPushV1 {
  if (
    !isObject(snapshot) || snapshot.schemaVersion !== 1 ||
    typeof snapshot.tripId !== "string" ||
    typeof snapshot.status !== "string" ||
    typeof snapshot.primaryFormat !== "string" ||
    !Array.isArray(snapshot.boards)
  ) {
    throw new ActivityKitPayloadError(
      "invalid_snapshot",
      "The leaderboard snapshot contract is invalid.",
    );
  }
  const revision = safeInteger(snapshot.revision, "revision");
  const generatedAt = typeof snapshot.generatedAt === "string"
    ? new Date(snapshot.generatedAt)
    : null;
  if (!generatedAt || !Number.isFinite(generatedAt.getTime())) {
    throw new ActivityKitPayloadError(
      "invalid_snapshot",
      "Snapshot generatedAt is invalid.",
    );
  }
  const primaryBoard =
    snapshot.boards.find((board) =>
      isObject(board) && board.format === snapshot.primaryFormat
    ) ?? snapshot.boards[0];
  const standings =
    isObject(primaryBoard) && Array.isArray(primaryBoard.standings)
      ? primaryBoard.standings.map(parseStanding).filter((
        value,
      ): value is StandingV1 => value !== null)
      : [];
  const leader = standings.find((standing) => standing.rank === 1) ??
    standings[0] ?? null;
  const viewer = viewerPlayerId
    ? standings.find((standing) => standing.playerId === viewerPlayerId) ?? null
    : null;
  const currentRound = isObject(snapshot.currentRound)
    ? snapshot.currentRound
    : null;
  const throughHole = currentRound
    ? safeInteger(currentRound.throughHole, "throughHole")
    : 0;
  const skinsBoard = snapshot.boards.find((board) =>
    isObject(board) && board.format === "skins"
  );
  const skinsCarry = isObject(skinsBoard) &&
      typeof skinsBoard.skinsCarry === "number" &&
      Number.isSafeInteger(skinsBoard.skinsCarry) && skinsBoard.skinsCarry >= 0
    ? skinsBoard.skinsCarry
    : null;
  const contentState: TeeCircleActivityContentStateV1 = {
    revision,
    status: snapshot.status,
    roundName: currentRound && typeof currentRound.name === "string"
      ? truncate(currentRound.name, 100)
      : null,
    throughHole,
    leaderName: leader ? truncate(leader.displayName, 100) : null,
    leaderValue: leader?.value ?? null,
    viewerRank: viewer?.rank ?? null,
    viewerValue: viewer?.value ?? null,
    skinsCarry,
    updatedAt: generatedAt.getTime() / 1_000 -
      APPLE_REFERENCE_DATE_UNIX_SECONDS,
  };
  const contentStateSize = byteLength(contentState);
  if (contentStateSize >= ACTIVITYKIT_CONTENT_STATE_LIMIT) {
    throw new ActivityKitPayloadError(
      "content_state_too_large",
      `Live Activity content-state is ${contentStateSize} bytes.`,
    );
  }

  const isFinal = snapshot.status === "completed" ||
    snapshot.status === "archived";
  const priority = activityKitPriorityV1(snapshot);
  const timestamp = Math.floor(now.getTime() / 1_000);
  const aps: Record<string, unknown> = {
    timestamp,
    event: isFinal ? "end" : "update",
    "content-state": contentState,
  };
  if (isFinal) {
    aps["dismissal-date"] = timestamp + 4 * 60 * 60;
  } else {
    aps["stale-date"] = timestamp + 20 * 60;
  }
  if (priority === 10) {
    const summary = isObject(snapshot.moment) &&
        typeof snapshot.moment.summary === "string"
      ? snapshot.moment.summary
      : isFinal
      ? "Final results are in."
      : "The live standings changed.";
    aps.alert = {
      title: "TeeCircle",
      body: truncate(summary, 160),
    };
  }
  const payload = { aps };
  const payloadSize = byteLength(payload);
  if (payloadSize >= ACTIVITYKIT_CONTENT_STATE_LIMIT) {
    throw new ActivityKitPayloadError(
      "apns_payload_too_large",
      `Live Activity APNs payload is ${payloadSize} bytes.`,
    );
  }
  return { payload, contentState, priority, isFinal };
}

export function base64UrlEncodeV1(input: string | Uint8Array): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/u,
    "",
  );
}

function privateKeyBytes(pem: string): ArrayBuffer {
  const normalized = pem.replaceAll("\\n", "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/gu, "");
  if (!base64) {
    throw new ActivityKitPayloadError(
      "apns_key_invalid",
      "The APNs private key is invalid.",
    );
  }
  try {
    const decoded = Uint8Array.from(
      atob(base64),
      (character) => character.charCodeAt(0),
    );
    const bytes = new Uint8Array(decoded.byteLength);
    bytes.set(decoded);
    return bytes.buffer;
  } catch {
    throw new ActivityKitPayloadError(
      "apns_key_invalid",
      "The APNs private key is invalid.",
    );
  }
}

export async function createApnsProviderTokenV1(
  teamId: string,
  keyId: string,
  privateKeyPem: string,
  now = new Date(),
): Promise<string> {
  if (!teamId || !keyId || !privateKeyPem) {
    throw new ActivityKitPayloadError(
      "apns_configuration_invalid",
      "APNs provider credentials are incomplete.",
    );
  }
  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const encodedHeader = base64UrlEncodeV1(
    JSON.stringify({ alg: "ES256", kid: keyId }),
  );
  const encodedClaims = base64UrlEncodeV1(JSON.stringify({
    iss: teamId,
    iat: Math.floor(now.getTime() / 1_000),
  }));
  const signingInput = `${encodedHeader}.${encodedClaims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${base64UrlEncodeV1(signature)}`;
}
