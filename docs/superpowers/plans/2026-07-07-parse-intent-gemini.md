# parse-intent Gemini Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Claude (Anthropic) call in the `parse-intent` Supabase edge function with a plain-fetch call to Gemini 2.5 Flash-Lite, preserving the function's request/response contract exactly.

**Architecture:** Pure helpers (schema, request builder, response extractor, validator) live in a new `gemini.ts` beside the function entrypoint so they are unit-testable with `deno test` without any network or server. `index.ts` keeps the HTTP wiring: auth guard, input check, one `fetch` to Gemini, error mapping. The `@anthropic-ai/sdk` dependency is removed.

**Tech Stack:** Deno (Supabase Edge Functions), Gemini REST API (`generateContent`, `responseSchema` structured output), `jsr:@std/assert` for tests.

**Spec:** `docs/superpowers/specs/2026-07-07-parse-intent-gemini-design.md`

## Global Constraints

- Model is exactly `gemini-2.5-flash-lite`; endpoint `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent`; auth via `x-goog-api-key` header (never in the URL).
- The HTTP contract with the app is unchanged: success → the parsed-intent JSON object; missing/blank transcript → 400; unauthenticated → 401; unusable model output → `{ "error": "model returned no parsable intent" }` 502; Gemini rate limit → 429; missing key → 500.
- `generationConfig`: `responseMimeType: "application/json"`, `responseSchema` (Task 1), `temperature: 0`, `maxOutputTokens: 512`.
- Gemini schema dialect: no JSON-Schema union types, no `additionalProperties`; nullability via `nullable: true`.
- `GEMINI_API_KEY` lives only in Supabase function secrets, never in code or git.
- Deploys must pass `--import-map supabase/functions/deno.json` (the CLI does not auto-detect it in this repo).
- All commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Gemini helpers (`gemini.ts`) with unit tests

**Files:**
- Create: `supabase/functions/parse-intent/gemini.ts`
- Test: `supabase/functions/parse-intent/gemini_test.ts`

**Interfaces:**
- Consumes: nothing from this repo (pure module).
- Produces (used by Task 2):
  - `type ParsedIntent = { courseQuery: string; date: string; timeStart: string; timeEnd: string; players: number; holes: 9 | 18 | null; needsClarification: boolean; confidence: number }`
  - `buildGeminiRequest(systemPrompt: string, transcript: string): object` — full JSON body for `generateContent`.
  - `extractResponseText(body: unknown): string | null` — joined text of `candidates[0].content.parts`, or null.
  - `validateIntent(value: unknown): ParsedIntent | null` — type-checks all eight keys, coerces `holes` to `9 | 18 | null`.

- [ ] **Step 1: Confirm deno is available**

Run: `deno --version || brew install deno`
Expected: version output (any 2.x is fine).

- [ ] **Step 2: Write the failing tests**

Create `supabase/functions/parse-intent/gemini_test.ts`:

```ts
import { assertEquals } from "jsr:@std/assert@1";
import {
  buildGeminiRequest,
  extractResponseText,
  validateIntent,
} from "./gemini.ts";

const FULL_INTENT = {
  courseQuery: "Bethpage Black",
  date: "2026-07-11",
  timeStart: "06:00",
  timeEnd: "12:00",
  players: 4,
  holes: 18,
  needsClarification: false,
  confidence: 0.95,
};

Deno.test("validateIntent accepts a complete valid intent", () => {
  assertEquals(validateIntent(FULL_INTENT), FULL_INTENT);
});

Deno.test("validateIntent coerces out-of-range holes to null", () => {
  assertEquals(validateIntent({ ...FULL_INTENT, holes: 27 })?.holes, null);
  assertEquals(validateIntent({ ...FULL_INTENT, holes: "18" })?.holes, null);
  assertEquals(validateIntent({ ...FULL_INTENT, holes: null })?.holes, null);
  assertEquals(validateIntent({ ...FULL_INTENT, holes: 9 })?.holes, 9);
});

Deno.test("validateIntent rejects missing or mistyped required keys", () => {
  const { date: _dropped, ...missingDate } = FULL_INTENT;
  assertEquals(validateIntent(missingDate), null);
  assertEquals(validateIntent({ ...FULL_INTENT, players: "4" }), null);
  assertEquals(validateIntent({ ...FULL_INTENT, players: 2.5 }), null);
  assertEquals(validateIntent(null), null);
  assertEquals(validateIntent("not an object"), null);
});

Deno.test("extractResponseText joins candidate parts", () => {
  const body = {
    candidates: [
      { content: { parts: [{ text: '{"a":' }, { text: "1}" }] } },
    ],
  };
  assertEquals(extractResponseText(body), '{"a":1}');
});

Deno.test("extractResponseText returns null when shape is wrong", () => {
  assertEquals(extractResponseText({}), null);
  assertEquals(extractResponseText(null), null);
  assertEquals(extractResponseText({ candidates: [] }), null);
  assertEquals(
    extractResponseText({ candidates: [{ content: { parts: [] } }] }),
    null,
  );
});

Deno.test("buildGeminiRequest wires prompt, transcript, and schema", () => {
  const req = buildGeminiRequest("SYSTEM", "four players tomorrow") as {
    systemInstruction: { parts: { text: string }[] };
    contents: { role: string; parts: { text: string }[] }[];
    generationConfig: {
      responseMimeType: string;
      responseSchema: { required: string[] };
      temperature: number;
      maxOutputTokens: number;
    };
  };
  assertEquals(req.systemInstruction.parts[0].text, "SYSTEM");
  assertEquals(req.contents[0].role, "user");
  assertEquals(req.contents[0].parts[0].text, "four players tomorrow");
  assertEquals(req.generationConfig.responseMimeType, "application/json");
  assertEquals(req.generationConfig.temperature, 0);
  assertEquals(req.generationConfig.maxOutputTokens, 512);
  assertEquals(req.generationConfig.responseSchema.required.length, 8);
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `deno test supabase/functions/parse-intent/gemini_test.ts`
Expected: FAIL — `Module not found ... gemini.ts`.

- [ ] **Step 4: Implement `gemini.ts`**

Create `supabase/functions/parse-intent/gemini.ts`:

```ts
// Pure helpers for the Gemini generateContent call made by index.ts.
// Gemini's responseSchema is an OpenAPI subset: no union types, no
// additionalProperties — nullability is expressed with nullable:true, and
// the 9/18 holes constraint is enforced by validateIntent instead.

export type ParsedIntent = {
  courseQuery: string;
  date: string;
  timeStart: string;
  timeEnd: string;
  players: number;
  holes: 9 | 18 | null;
  needsClarification: boolean;
  confidence: number;
};

export const GEMINI_INTENT_SCHEMA = {
  type: "object",
  required: [
    "courseQuery",
    "date",
    "timeStart",
    "timeEnd",
    "players",
    "holes",
    "needsClarification",
    "confidence",
  ],
  properties: {
    courseQuery: {
      type: "string",
      description:
        'The course the user named, as they said it. Use "local" when they want any nearby course or did not name one.',
    },
    date: {
      type: "string",
      description:
        "The requested date resolved to an absolute ISO date, YYYY-MM-DD.",
    },
    timeStart: {
      type: "string",
      description: "Earliest acceptable tee time, HH:MM 24-hour.",
    },
    timeEnd: {
      type: "string",
      description: "Latest acceptable tee time, HH:MM 24-hour.",
    },
    players: {
      type: "integer",
      description: "Number of players. Default 1 if unstated.",
    },
    holes: {
      type: "integer",
      nullable: true,
      description: "Exactly 9 or 18 when the user specified, otherwise null.",
    },
    needsClarification: {
      type: "boolean",
      description:
        "True when the request is too ambiguous to search (e.g. no date can be inferred).",
    },
    confidence: {
      type: "number",
      description: "0-1 confidence that this intent matches what was said.",
    },
  },
} as const;

export function buildGeminiRequest(systemPrompt: string, transcript: string) {
  return {
    systemInstruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts: [{ text: transcript }] }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: GEMINI_INTENT_SCHEMA,
      temperature: 0,
      maxOutputTokens: 512,
    },
  };
}

export function extractResponseText(body: unknown): string | null {
  const candidates = (body as { candidates?: unknown })?.candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const parts = (candidates[0] as { content?: { parts?: unknown } })?.content
    ?.parts;
  if (!Array.isArray(parts)) return null;
  const text = parts
    .map((p) => (typeof (p as { text?: unknown })?.text === "string"
      ? (p as { text: string }).text
      : ""))
    .join("");
  return text.trim().length > 0 ? text : null;
}

export function validateIntent(value: unknown): ParsedIntent | null {
  if (typeof value !== "object" || value === null) return null;
  const v = value as Record<string, unknown>;
  if (
    typeof v.courseQuery !== "string" ||
    typeof v.date !== "string" ||
    typeof v.timeStart !== "string" ||
    typeof v.timeEnd !== "string" ||
    typeof v.players !== "number" ||
    !Number.isInteger(v.players) ||
    typeof v.needsClarification !== "boolean" ||
    typeof v.confidence !== "number"
  ) {
    return null;
  }
  const holes = v.holes === 9 || v.holes === 18 ? v.holes : null;
  return {
    courseQuery: v.courseQuery,
    date: v.date,
    timeStart: v.timeStart,
    timeEnd: v.timeEnd,
    players: v.players,
    holes,
    needsClarification: v.needsClarification,
    confidence: v.confidence,
  };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test supabase/functions/parse-intent/gemini_test.ts`
Expected: PASS — 6 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/parse-intent/gemini.ts supabase/functions/parse-intent/gemini_test.ts
git commit -m "Add Gemini request/validation helpers for parse-intent

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Rewire `index.ts` to Gemini and drop the Anthropic SDK

**Files:**
- Modify: `supabase/functions/parse-intent/index.ts` (whole file below)
- Modify: `supabase/functions/deno.json` (remove `@anthropic-ai/sdk` entry)

**Interfaces:**
- Consumes from Task 1: `buildGeminiRequest(systemPrompt: string, transcript: string): object`, `extractResponseText(body: unknown): string | null`, `validateIntent(value: unknown): ParsedIntent | null`, `type ParsedIntent`.
- Produces: the deployed HTTP contract in Global Constraints. Nothing else imports this file.

- [ ] **Step 1: Replace `index.ts`**

Replace the entire contents of `supabase/functions/parse-intent/index.ts` with:

```ts
// parse-intent: turn a voice transcript into a structured tee-time search intent.
//
// Uses Gemini (gemini-2.5-flash-lite) with a JSON responseSchema, then
// re-validates the output in validateIntent since Gemini's schema
// enforcement is looser than a strict JSON-Schema guarantee.
// GEMINI_API_KEY lives ONLY in Supabase function secrets
// (supabase secrets set GEMINI_API_KEY=...), never in code.

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import {
  buildGeminiRequest,
  extractResponseText,
  type ParsedIntent,
  validateIntent,
} from "./gemini.ts";

const EASTERN = "America/New_York";

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent";

function todayInEastern(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: EASTERN,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function weekdayInEastern(): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: EASTERN,
    weekday: "long",
  }).format(new Date());
}

function buildSystemPrompt(): string {
  return [
    "You extract a golf tee-time search intent from a voice transcript.",
    `Today is ${weekdayInEastern()}, ${todayInEastern()} in the ${EASTERN} timezone. Resolve all relative dates ("tomorrow", "next Tuesday", "this weekend") against that date and return an absolute YYYY-MM-DD.`,
    'If the user names no course or asks for something nearby/local, set courseQuery to "local".',
    "If no time window is given, use 06:00 to 19:00. If they say morning use 06:00-12:00, afternoon 12:00-17:00, evening 16:00-20:00.",
    "If the number of players is unstated, use 1.",
    "Set holes to 9 or 18 only when the user says so; otherwise null.",
    "Set needsClarification to true only when you cannot produce a usable search (no inferable date, or an unintelligible transcript).",
  ].join("\n");
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    await requireUser(req);

    const body = await req.json().catch(() => null);
    const transcript = body?.transcript;
    if (typeof transcript !== "string" || transcript.trim().length === 0) {
      return jsonResponse({ error: "transcript (string) is required" }, 400);
    }

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return jsonResponse({ error: "GEMINI_API_KEY is not configured" }, 500);
    }

    const geminiRes = await fetch(GEMINI_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify(buildGeminiRequest(buildSystemPrompt(), transcript)),
    });

    if (geminiRes.status === 429) {
      return jsonResponse(
        { error: "rate limited, try again shortly" },
        429,
      );
    }
    if (!geminiRes.ok) {
      console.error("gemini error:", geminiRes.status, await geminiRes.text());
      return jsonResponse({ error: "intent service unavailable" }, 502);
    }

    const geminiBody = await geminiRes.json().catch(() => null);
    const text = extractResponseText(geminiBody);
    let intent: ParsedIntent | null = null;
    if (text !== null) {
      try {
        intent = validateIntent(JSON.parse(text));
      } catch {
        intent = null;
      }
    }
    if (intent === null) {
      return jsonResponse({ error: "model returned no parsable intent" }, 502);
    }
    return jsonResponse(intent);
  } catch (err) {
    if (err instanceof AuthError) {
      return jsonResponse({ error: err.message }, 401);
    }
    console.error("parse-intent failed:", err);
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
```

- [ ] **Step 2: Remove the Anthropic entry from the import map**

Replace the entire contents of `supabase/functions/deno.json` with:

```json
{
  "imports": {
    "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2"
  }
}
```

- [ ] **Step 3: Typecheck the function**

Run: `deno check --config supabase/functions/deno.json supabase/functions/parse-intent/index.ts`
Expected: exits 0 (remote esm.sh fetch on first run is normal).

- [ ] **Step 4: Re-run the unit tests**

Run: `deno test supabase/functions/parse-intent/gemini_test.ts`
Expected: PASS — 6 tests, 0 failures.

- [ ] **Step 5: Verify no Anthropic references remain in the function**

Run: `grep -ri anthropic supabase/functions/`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/parse-intent/index.ts supabase/functions/deno.json
git commit -m "Switch parse-intent from Claude to Gemini 2.5 Flash-Lite

Plain fetch to generateContent with a JSON responseSchema; drops the
@anthropic-ai/sdk dependency. Contract with the app is unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Deploy, secret, and end-to-end verification

**Files:**
- None modified. Operates on the deployed TeeCircle Supabase project `zgrbwhnfuxgvkwtgrncu` (user-authorized deploy target).

**Interfaces:**
- Consumes: the committed function from Task 2.
- Produces: live `parse-intent` v2 on Supabase.

- [ ] **Step 1: Set the Gemini secret (HUMAN — Luke)**

Luke creates a free key at https://aistudio.google.com and either adds `GEMINI_API_KEY` in the dashboard (Project Settings → Edge Functions → Secrets) or runs, with the real key:

```
! npx supabase secrets set GEMINI_API_KEY=AIza... --project-ref zgrbwhnfuxgvkwtgrncu
```

Verify: `npx supabase secrets list --project-ref zgrbwhnfuxgvkwtgrncu` shows `GEMINI_API_KEY`.

- [ ] **Step 2: Deploy**

Run: `npx supabase functions deploy parse-intent --project-ref zgrbwhnfuxgvkwtgrncu --import-map supabase/functions/deno.json`
Expected: `"message":"Deployed Functions."`; dashboard shows `parse-intent` version 2.

- [ ] **Step 3: Unauthenticated smoke test**

Run:

```bash
curl -s -w " [HTTP %{http_code}]" -X POST \
  "https://zgrbwhnfuxgvkwtgrncu.supabase.co/functions/v1/parse-intent" \
  -H "Content-Type: application/json" -d '{}'
```

Expected: `{"code":"UNAUTHORIZED_NO_AUTH_HEADER",...} [HTTP 401]` — function boots, auth guard intact.

- [ ] **Step 4: Authenticated end-to-end test**

Get a user JWT via the password grant (Luke supplies a real test-account email/password; `EXPO_PUBLIC_SUPABASE_ANON_KEY` is in `.env`):

```bash
ANON_KEY=$(grep EXPO_PUBLIC_SUPABASE_ANON_KEY .env | cut -d= -f2)
TOKEN=$(curl -s "https://zgrbwhnfuxgvkwtgrncu.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"<TEST_EMAIL>","password":"<TEST_PASSWORD>"}' | jq -r .access_token)
curl -s -X POST "https://zgrbwhnfuxgvkwtgrncu.supabase.co/functions/v1/parse-intent" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"transcript":"find me a tee time tomorrow morning for four players"}'
```

Expected: JSON with all eight intent keys; `date` = tomorrow's Eastern date; `timeStart` `06:00`; `timeEnd` `12:00`; `players` 4; `holes` null; `needsClarification` false.

- [ ] **Step 5: Rate-limit sanity note (no action)**

If Step 4 ever returns HTTP 429, that is the free-tier limit (15 req/min) passing through as designed — wait a minute and retry.
