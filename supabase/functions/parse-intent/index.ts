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
