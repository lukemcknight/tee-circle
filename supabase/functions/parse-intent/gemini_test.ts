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
  holes: 18 as const,
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
      responseSchema: { required: readonly string[] };
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
