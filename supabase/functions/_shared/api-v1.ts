import { corsHeaders } from "./cors.ts";

export interface ApiErrorBody {
  code: string;
  message: string;
  retryable: boolean;
  currentRevision?: number;
  details?: unknown;
}

export type ApiEnvelope<T> =
  | { schemaVersion: 1; requestId: string; data: T }
  | { schemaVersion: 1; requestId: string; error: ApiErrorBody };

export function requestId(): string {
  return crypto.randomUUID();
}

export function success<T>(id: string, data: T, status = 200): Response {
  return response({ schemaVersion: 1, requestId: id, data }, status);
}

export function failure(
  id: string,
  status: number,
  code: string,
  message: string,
  retryable = false,
  currentRevision?: number,
  details?: unknown,
): Response {
  const error: ApiErrorBody = { code, message, retryable };
  if (currentRevision !== undefined) error.currentRevision = currentRevision;
  if (details !== undefined) error.details = details;
  return response({ schemaVersion: 1, requestId: id, error }, status);
}

export function response<T>(body: ApiEnvelope<T>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isErrorEnvelope(
  value: unknown,
): value is ApiEnvelope<never> & { error: ApiErrorBody } {
  return isObject(value) && isObject(value.error) &&
    typeof value.error.code === "string";
}

export function isApiEnvelope(value: unknown): value is ApiEnvelope<unknown> {
  return isObject(value) &&
    value.schemaVersion === 1 &&
    typeof value.requestId === "string" &&
    ("data" in value || isErrorEnvelope(value));
}
