import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  PREVIEW_PROXY_SECRET_HEADER,
  PREVIEW_PROXY_VIEWER_HEADER,
  previewRateLimitIdentity,
  previewRateLimitSubjectHash,
} from "./rate-limit.ts";

Deno.test("preview proxy identity is trusted only with the matching secret", () => {
  const headers = new Headers({
    [PREVIEW_PROXY_SECRET_HEADER]: "shared-secret",
    [PREVIEW_PROXY_VIEWER_HEADER]: "203.0.113.8",
    "cf-connecting-ip": "198.51.100.20",
  });

  assertEquals(previewRateLimitIdentity(headers, "shared-secret"), {
    source: "verified_proxy",
    value: "203.0.113.8",
  });
  assertEquals(previewRateLimitIdentity(headers, "wrong-secret"), {
    source: "direct_edge",
    value: "198.51.100.20",
  });
  assertEquals(previewRateLimitIdentity(headers, undefined), {
    source: "direct_edge",
    value: "198.51.100.20",
  });
});

Deno.test("unverified forwarding chains use the nearest edge hop", () => {
  const headers = new Headers({
    [PREVIEW_PROXY_VIEWER_HEADER]: "203.0.113.8",
    "x-forwarded-for": "192.0.2.4, 198.51.100.25",
  });

  assertEquals(previewRateLimitIdentity(headers, "shared-secret"), {
    source: "direct_edge",
    value: "198.51.100.25",
  });
});

Deno.test("preview subjects are opaque and isolated by invitation", async () => {
  const identity = {
    source: "verified_proxy" as const,
    value: "203.0.113.8",
  };
  const first = await previewRateLimitSubjectHash("salt", identity, "token-a");
  const second = await previewRateLimitSubjectHash("salt", identity, "token-b");

  assertNotEquals(first, second);
  assertEquals(first.length, 64);
  assertEquals(first.includes("203.0.113.8"), false);
});
