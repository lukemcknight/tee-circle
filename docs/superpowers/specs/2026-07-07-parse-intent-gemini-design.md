# parse-intent: switch from Claude to Gemini

**Date:** 2026-07-07
**Status:** Approved (conversation) — pending written-spec review
**Motivation:** Zero API cost. Google AI Studio's free tier covers Gemini 2.5 Flash-Lite at 15 req/min and 1,000 req/day — far above current usage — with no card required. Also consolidates on Google (already used for OAuth sign-in).

## Scope

One edge function: `supabase/functions/parse-intent/index.ts`, plus its import map entry in `supabase/functions/deno.json`. Nothing else changes. The app is untouched — the function's request/response contract is preserved exactly, so no client rebuild is needed.

## Approach (chosen)

Plain `fetch` to the Gemini REST API. No SDK. The `@anthropic-ai/sdk` import-map entry is deleted (`@supabase/supabase-js` stays — `_shared/auth.ts` uses it).

Rejected alternatives: `@google/genai` SDK (adds a dependency for one call; import-map friction), dual-provider env switch (YAGNI; Claude is one `git revert` away).

## Design

### Request to Gemini

- `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent`
- Auth via `x-goog-api-key: ${GEMINI_API_KEY}` header.
- Body:
  - `systemInstruction`: the existing `buildSystemPrompt()` text, unchanged.
  - `contents`: single user turn containing the transcript.
  - `generationConfig`: `responseMimeType: "application/json"`, `responseSchema` (below), `temperature: 0`, `maxOutputTokens: 512`.

### Schema translation

Gemini's `responseSchema` is an OpenAPI 3.0 subset, not full JSON Schema:

- `holes: { type: ["integer","null"], enum: [9,18,null] }` becomes `{ type: "integer", nullable: true }` with the 9/18 constraint stated in the `description` (Gemini enums are string-typed only).
- `additionalProperties: false` is dropped (unsupported).
- All other fields translate 1:1 (`type`, `required`, `description`).

### Post-parse validation (new)

Because Gemini's schema enforcement is looser than Claude structured outputs, add a small `validateIntent()` guard after `JSON.parse` of `candidates[0].content.parts[0].text`:

- All eight required keys present with correct primitive types.
- `holes` coerced to `9 | 18 | null` (anything else → `null`).
- On failure: return `{ error: "model returned no parsable intent" }` with status 502 — same contract as today.

### Error mapping

- Missing `GEMINI_API_KEY` → 500 (message updated from the Anthropic name).
- Gemini HTTP 429 (free-tier rate limit) → pass through as 429 so the app can show "try again in a minute".
- Other non-OK Gemini responses → 502 with a short message; details to `console.error`.
- `AuthError` → 401, unchanged. Unknown errors → 500, unchanged.

### Secrets

- Add `GEMINI_API_KEY` (free key from aistudio.google.com) to Supabase function secrets.
- `ANTHROPIC_API_KEY` is no longer read; it was never set, so there is nothing to remove.

## Testing

1. `deno check` the function locally (typecheck only; no Docker requirement).
2. Deploy with `--import-map supabase/functions/deno.json` (established requirement from the first deploy).
3. Smoke test: unauthenticated POST → 401 (proves boot + auth guard).
4. End-to-end: authenticated request with a real transcript once `GEMINI_API_KEY` is set — verify a valid `ParsedIntent` comes back, spot-check relative-date resolution ("tomorrow morning").

## Rollback

`git revert` of the single commit restores Claude; redeploy. No data or schema migrations involved.

## Caveat

Free-tier Gemini traffic may be used by Google for product improvement. Payload here is tee-time voice transcripts (course, date, players) — accepted as low-sensitivity.
