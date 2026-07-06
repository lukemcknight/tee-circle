// search-tee-times: resolve a parsed intent to a course (or set of nearby
// courses), fetch live availability from Kenna/TeeItUp, and filter it to the
// intent's time window, party size, and holes.
//
// Response is a discriminated union (see SearchResponse in _shared/types.ts):
//   bookable   -> live slots the app can book
//   unbookable -> a known course we can only deep-link to
//   unknown    -> the query matched no registered course
//   error      -> Kenna failed or returned an unexpected shape

import { AuthError, requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import {
  type BookableCourse,
  bookableCourses,
  findCourse,
  haversineKm,
  isGenericQuery,
} from "../_shared/registry.ts";
import { fetchTeeTimes, KennaHttpError, ParseError } from "../_shared/teeitup.ts";
import type {
  ParsedIntent,
  SearchRequest,
  SearchResponse,
  TeeTimeSlot,
} from "../_shared/types.ts";

const NEARBY_RADIUS_KM = 40;

function isValidIntent(intent: unknown): intent is ParsedIntent {
  if (typeof intent !== "object" || intent === null) return false;
  const i = intent as Record<string, unknown>;
  return (
    typeof i.courseQuery === "string" &&
    typeof i.date === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(i.date) &&
    typeof i.timeStart === "string" &&
    typeof i.timeEnd === "string" &&
    typeof i.players === "number" &&
    (i.holes === null || i.holes === 9 || i.holes === 18)
  );
}

/** Fetch slots for a set of bookable courses: one Kenna GET per distinct alias. */
async function searchCourses(
  courses: BookableCourse[],
  date: string,
): Promise<TeeTimeSlot[]> {
  const byAlias = new Map<string, BookableCourse[]>();
  for (const course of courses) {
    const group = byAlias.get(course.alias) ?? [];
    group.push(course);
    byAlias.set(course.alias, group);
  }
  const results = await Promise.all(
    [...byAlias.entries()].map(([alias, group]) => fetchTeeTimes(alias, group, date)),
  );
  return results.flat();
}

function filterSlots(slots: TeeTimeSlot[], intent: ParsedIntent): TeeTimeSlot[] {
  return slots.filter((slot) => {
    // teetimeIso is Eastern local time: "YYYY-MM-DDTHH:MM:SS±HH:MM".
    const localTime = slot.teetimeIso.slice(11, 16);
    if (intent.timeStart && localTime < intent.timeStart) return false;
    if (intent.timeEnd && localTime > intent.timeEnd) return false;
    if (slot.maxPlayers < intent.players) return false;
    if (slot.minPlayers > intent.players) return false;
    if (intent.holes !== null && slot.holes !== intent.holes) return false;
    return true;
  });
}

async function search(intent: ParsedIntent, coords: SearchRequest["coords"]): Promise<SearchResponse> {
  // (1) Generic "local"/"nearby" query -> all bookable courses, distance-filtered.
  if (isGenericQuery(intent.courseQuery)) {
    let candidates = bookableCourses();
    if (coords) {
      const nearby = candidates.filter(
        (c) => haversineKm(coords.lat, coords.lng, c.lat, c.lng) <= NEARBY_RADIUS_KM,
      );
      if (nearby.length > 0) candidates = nearby;
    }
    const slots = await searchCourses(candidates, intent.date);
    return { kind: "bookable", slots: filterSlots(slots, intent) };
  }

  // (2)-(4) Specific course: fuzzy-match against the registry.
  const course = findCourse(intent.courseQuery);
  if (course === null) {
    return { kind: "unknown", courseQuery: intent.courseQuery };
  }
  if (!course.bookable) {
    return {
      kind: "unbookable",
      name: course.name,
      externalUrl: course.externalUrl,
      reason: course.reason,
    };
  }
  const slots = await searchCourses([course], intent.date);
  return { kind: "bookable", slots: filterSlots(slots, intent) };
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    await requireUser(req);

    const body = (await req.json().catch(() => null)) as SearchRequest | null;
    if (!body || !isValidIntent(body.intent)) {
      return jsonResponse({ error: "intent with courseQuery/date/timeStart/timeEnd/players/holes is required" }, 400);
    }
    const coords =
      body.coords &&
        typeof body.coords.lat === "number" &&
        typeof body.coords.lng === "number"
        ? body.coords
        : null;

    let result: SearchResponse;
    try {
      result = await search(body.intent, coords);
    } catch (err) {
      // Kenna failure or schema drift is an in-band result, not a 500 —
      // the app renders it as a friendly "search failed" state.
      if (err instanceof ParseError || err instanceof KennaHttpError) {
        result = { kind: "error", message: err.message };
      } else {
        throw err;
      }
    }
    return jsonResponse(result);
  } catch (err) {
    if (err instanceof AuthError) {
      return jsonResponse({ error: err.message }, 401);
    }
    console.error("search-tee-times failed:", err);
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: message }, 500);
  }
});
