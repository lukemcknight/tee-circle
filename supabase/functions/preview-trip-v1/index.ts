import { createAdminClient } from "../_shared/admin.ts";
import { failure, isObject, requestId, success } from "../_shared/api-v1.ts";
import { handleOptions } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/crypto.ts";
import {
  previewRateLimitIdentity,
  previewRateLimitSubjectHash,
} from "./rate-limit.ts";

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{40,128}$/;

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  const id = requestId();

  if (req.method !== "POST") {
    return failure(
      id,
      405,
      "method_not_allowed",
      "Use POST for trip previews.",
    );
  }

  try {
    const body: unknown = await req.json().catch(() => null);
    if (
      !isObject(body) || body.schemaVersion !== 1 ||
      typeof body.inviteToken !== "string"
    ) {
      return failure(
        id,
        400,
        "invalid_request",
        "schemaVersion 1 and inviteToken are required.",
      );
    }
    const inviteToken = body.inviteToken.trim();
    if (!TOKEN_PATTERN.test(inviteToken)) {
      return failure(
        id,
        404,
        "invite_unavailable",
        "This trip invitation is unavailable.",
      );
    }

    const tokenHash = await sha256Hex(inviteToken);
    const identity = previewRateLimitIdentity(
      req.headers,
      Deno.env.get("PUBLIC_PREVIEW_PROXY_SECRET"),
    );
    const rateSalt = Deno.env.get("PUBLIC_RATE_LIMIT_SALT")?.trim();
    if (!rateSalt) {
      console.error("preview rate-limit salt is not configured", {
        requestId: id,
      });
      return failure(
        id,
        503,
        "preview_unavailable",
        "Trip preview is temporarily unavailable.",
        true,
      );
    }
    const subjectHash = await previewRateLimitSubjectHash(
      rateSalt,
      identity,
      tokenHash,
    );
    const admin = createAdminClient();
    const { data: allowed, error: rateError } = await admin.rpc(
      "consume_public_rate_limit_service_v1",
      {
        p_subject_hash_hex: subjectHash,
        p_route: "preview-trip-v1",
        p_limit: 60,
        p_window_seconds: 60,
      },
    );
    if (rateError) {
      console.error("preview rate-limit failure", {
        requestId: id,
        error: rateError.message,
      });
      return failure(
        id,
        503,
        "preview_unavailable",
        "Trip preview is temporarily unavailable.",
        true,
      );
    }
    if (allowed !== true) {
      return failure(
        id,
        429,
        "rate_limited",
        "Too many preview requests. Try again shortly.",
        true,
      );
    }

    const { data, error } = await admin.rpc(
      "resolve_public_trip_preview_service_v1",
      {
        p_token_hash_hex: tokenHash,
      },
    );
    if (error) {
      console.error("preview resolve failure", {
        requestId: id,
        error: error.message,
      });
      return failure(
        id,
        503,
        "preview_unavailable",
        "Trip preview is temporarily unavailable.",
        true,
      );
    }
    if (isObject(data) && typeof data.errorCode === "string") {
      const code = data.errorCode === "invite_revoked" ||
          data.errorCode === "invite_expired"
        ? data.errorCode
        : "invite_unavailable";
      const message = code === "invite_revoked"
        ? "This trip invitation was revoked."
        : code === "invite_expired"
        ? "This trip invitation expired."
        : "This trip invitation is unavailable.";
      return failure(
        id,
        code === "invite_unavailable" ? 404 : 410,
        code,
        message,
      );
    }
    if (!isObject(data) || !isObject(data.trip)) {
      return failure(
        id,
        404,
        "invite_unavailable",
        "This trip invitation is expired, revoked, or unavailable.",
      );
    }

    return success(id, {
      trip: data.trip,
      snapshot: data.snapshot ?? null,
    });
  } catch (error) {
    console.error("preview-trip-v1 failed", { requestId: id, error });
    return failure(
      id,
      500,
      "internal_error",
      "Trip preview is temporarily unavailable.",
      true,
    );
  }
});
