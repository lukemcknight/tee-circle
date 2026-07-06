// parse-intent: turn a voice transcript into a structured tee-time search intent.
//
// Uses Claude with structured outputs so the response always matches the
// ParsedIntent schema. ANTHROPIC_API_KEY lives ONLY in Supabase function
// secrets (supabase secrets set ANTHROPIC_API_KEY=...), never in code.

import Anthropic from "@anthropic-ai/sdk";
import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";

const EASTERN = "America/New_York";

// All fields required + additionalProperties:false, per structured-outputs rules.
const INTENT_SCHEMA = {
  type: "object",
  additionalProperties: false,
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
      type: ["integer", "null"],
      enum: [9, 18, null],
      description: "9 or 18 when the user specified, otherwise null.",
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

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return jsonResponse({ error: "ANTHROPIC_API_KEY is not configured" }, 500);
    }
    const client = new Anthropic({ apiKey });

    // Plain call — no thinking/effort params (claude-haiku-4-5 rejects them).
    const msg = await client.messages.parse({
      model: "claude-haiku-4-5",
      max_tokens: 512,
      system: buildSystemPrompt(),
      messages: [{ role: "user", content: transcript }],
      output_config: {
        format: { type: "json_schema", schema: INTENT_SCHEMA },
      },
    });

    if (msg.parsed_output == null) {
      return jsonResponse({ error: "model returned no parsable intent" }, 502);
    }
    return jsonResponse(msg.parsed_output);
  } catch (err) {
    if (err instanceof AuthError) {
      return jsonResponse({ error: err.message }, 401);
    }
    console.error("parse-intent failed:", err);
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
