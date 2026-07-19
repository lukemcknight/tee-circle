import { sha256Hex, timingSafeStringEqual } from "../_shared/crypto.ts";

export const PREVIEW_PROXY_SECRET_HEADER = "x-teecircle-preview-proxy-secret";
export const PREVIEW_PROXY_VIEWER_HEADER = "x-teecircle-preview-viewer";

const NETWORK_IDENTITY_PATTERN = /^[0-9a-f:.]{2,64}$/i;

export interface PreviewRateLimitIdentity {
  source: "verified_proxy" | "direct_edge" | "unknown";
  value: string;
}

function cleanNetworkIdentity(value: string | null | undefined): string | null {
  const candidate = value?.trim();
  return candidate && NETWORK_IDENTITY_PATTERN.test(candidate)
    ? candidate
    : null;
}

function directEdgeIdentity(headers: Headers): string | null {
  const cloudflareIP = cleanNetworkIdentity(headers.get("cf-connecting-ip"));
  if (cloudflareIP) return cloudflareIP;

  const realIP = cleanNetworkIdentity(headers.get("x-real-ip"));
  if (realIP) return realIP;

  // The nearest hop is last in a forwarding chain. This avoids trusting a
  // caller-controlled first entry when the platform provides only XFF.
  const forwarded = headers.get("x-forwarded-for")
    ?.split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return cleanNetworkIdentity(forwarded?.at(-1));
}

export function previewRateLimitIdentity(
  headers: Headers,
  expectedProxySecret: string | undefined,
): PreviewRateLimitIdentity {
  const configuredSecret = expectedProxySecret?.trim();
  const suppliedSecret = headers.get(PREVIEW_PROXY_SECRET_HEADER)?.trim();
  const forwardedViewer = cleanNetworkIdentity(
    headers.get(PREVIEW_PROXY_VIEWER_HEADER),
  );

  if (
    configuredSecret && suppliedSecret && forwardedViewer &&
    timingSafeStringEqual(configuredSecret, suppliedSecret)
  ) {
    return { source: "verified_proxy", value: forwardedViewer };
  }

  const direct = directEdgeIdentity(headers);
  return direct
    ? { source: "direct_edge", value: direct }
    : { source: "unknown", value: "unknown" };
}

export async function previewRateLimitSubjectHash(
  salt: string,
  identity: PreviewRateLimitIdentity,
  inviteTokenHash: string,
): Promise<string> {
  // Hash before this value crosses the database boundary. The invitation hash
  // isolates buckets, so traffic for one shared trip cannot starve another.
  return await sha256Hex(
    `${salt}\u0000preview-trip-v2\u0000${identity.source}\u0000${identity.value}\u0000${inviteTokenHash}`,
  );
}
