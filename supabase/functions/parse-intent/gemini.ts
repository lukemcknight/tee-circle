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
    .map((p) =>
      typeof (p as { text?: unknown })?.text === "string"
        ? (p as { text: string }).text
        : ""
    )
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
