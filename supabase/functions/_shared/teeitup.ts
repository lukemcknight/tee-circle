// TeeItUp (GolfNow/NBC white-label; Kenna backend) integration.
//
// Faithful TypeScript port of tee-time-sniper's src/sniper/scrapers/teeitup.py.
// One GET per (tenant alias, date) covers every facility of that tenant.
// The response is a top-level list of per-facility groups, each holding
// `teetimes[]`. The group-level `courseId` is a Kenna-internal id — the
// reliable mapping back to our courses is `rates[].golfnow.GolfFacilityId`.
//
// Parsing deliberately throws ParseError on any unexpected shape so Kenna
// schema drift surfaces as an error, not a silent empty list.

import type { BookableCourse } from "./registry.ts";
import type { TeeTimeSlot } from "./types.ts";

export const DEFAULT_KENNA_BASE_URL = "https://phx-api-be-east-1b.kenna.io";
const EASTERN = "America/New_York";

/** Kenna returned a shape we don't recognize — schema drift, not "no tee times". */
export class ParseError extends Error {
  override name = "ParseError";
}

/** Kenna responded with a non-2xx status. */
export class KennaHttpError extends Error {
  override name = "KennaHttpError";
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

/** Base URL may rotate; override via the KENNA_BASE_URL function secret. */
export function kennaBaseUrl(): string {
  return Deno.env.get("KENNA_BASE_URL") ?? DEFAULT_KENNA_BASE_URL;
}

/**
 * Fetch and parse all tee times for one tenant alias on one date.
 * `courses` must all belong to the given alias.
 */
export async function fetchTeeTimes(
  alias: string,
  courses: BookableCourse[],
  date: string,
): Promise<TeeTimeSlot[]> {
  const wrongTenant = courses.filter((c) => c.alias !== alias);
  if (wrongTenant.length > 0) {
    throw new Error(
      `one fetch per tenant; got courses from other aliases: ${wrongTenant.map((c) => c.id).join(", ")}`,
    );
  }
  const url = new URL(`${kennaBaseUrl()}/v2/tee-times`);
  url.searchParams.set("date", date);
  url.searchParams.set(
    "facilityIds",
    courses.map((c) => String(c.facilityId)).sort().join(","),
  );
  const res = await fetch(url, { headers: { "x-be-alias": alias } });
  if (!res.ok) {
    throw new KennaHttpError(res.status, `Kenna request failed: HTTP ${res.status}`);
  }
  const payload: unknown = await res.json();
  const byFacility = new Map(courses.map((c) => [c.facilityId, c]));
  return parseTeetimes(payload, byFacility, alias, date);
}

export function parseTeetimes(
  payload: unknown,
  facilityToCourse: Map<number, BookableCourse>,
  alias: string,
  date: string,
): TeeTimeSlot[] {
  if (!Array.isArray(payload)) {
    throw new ParseError(`expected top-level list, got: ${snippet(payload)}`);
  }

  const slots: TeeTimeSlot[] = [];
  for (const group of payload) {
    const teetimes = isRecord(group) ? group.teetimes : undefined;
    if (!Array.isArray(teetimes)) {
      throw new ParseError(`group without teetimes list: ${snippet(group)}`);
    }
    for (const teetime of teetimes) {
      slots.push(...parseTeetime(teetime, facilityToCourse, alias, date));
    }
  }
  slots.sort((a, b) =>
    a.courseId.localeCompare(b.courseId) ||
    a.teetimeIso.localeCompare(b.teetimeIso) ||
    a.holes - b.holes
  );
  return slots;
}

function parseTeetime(
  teetime: unknown,
  facilityToCourse: Map<number, BookableCourse>,
  alias: string,
  date: string,
): TeeTimeSlot[] {
  if (!isRecord(teetime)) {
    throw new ParseError(`teetime is not an object: ${snippet(teetime)}`);
  }
  const rates = teetime.rates;
  if (!Array.isArray(rates)) {
    throw new ParseError(`teetime without rates list: ${snippet(teetime)}`);
  }
  if (rates.length === 0) return [];

  const teetimeIso = parseWhen(teetime);
  const backNine = Boolean(teetime.backNine ?? false);

  // Group rates by (facility, holes): one slot per group. A teetime offering
  // both 9- and 18-hole rates becomes two slots.
  const groups = new Map<string, { facilityId: number; holes: number; rates: Record<string, unknown>[] }>();
  for (const rate of rates) {
    if (!isRecord(rate)) {
      throw new ParseError(`rate is not an object: ${snippet(rate)}`);
    }
    const golfnow = isRecord(rate.golfnow) ? rate.golfnow : undefined;
    const facilityIdRaw = golfnow?.GolfFacilityId;
    if (facilityIdRaw === null || facilityIdRaw === undefined) {
      console.warn(`rate without golfnow.GolfFacilityId, skipping: ${snippet(rate)}`);
      continue;
    }
    const holes = rate.holes;
    if (typeof holes !== "number" || !Number.isInteger(holes)) {
      throw new ParseError(`rate without holes: ${snippet(rate)}`);
    }
    if (!("allowedPlayers" in rate)) {
      throw new ParseError(`rate without allowedPlayers: ${snippet(rate)}`);
    }
    const facilityId = Number(facilityIdRaw);
    const key = `${facilityId}:${holes}`;
    const group = groups.get(key) ?? { facilityId, holes, rates: [] };
    group.rates.push(rate);
    groups.set(key, group);
  }

  const slots: TeeTimeSlot[] = [];
  for (const { facilityId, holes, rates: group } of groups.values()) {
    const course = facilityToCourse.get(facilityId);
    if (course === undefined) {
      console.warn(`teetime for unknown facility ${facilityId}, skipping`);
      continue;
    }
    const playerOptions = group.flatMap((r) =>
      Array.isArray(r.allowedPlayers) ? r.allowedPlayers.filter((n): n is number => typeof n === "number") : []
    );
    if (playerOptions.length === 0 || Math.max(...playerOptions) < 1) {
      continue; // not bookable
    }
    const prices = group
      .map((r) => r.greenFeeCart)
      .filter((p): p is number => p !== null && p !== undefined && typeof p === "number");
    slots.push({
      courseId: course.id,
      courseName: course.name,
      facilityId,
      alias,
      teetimeIso,
      holes: holes as 9 | 18,
      backNine,
      minPlayers: Math.min(...playerOptions),
      maxPlayers: Math.max(...playerOptions),
      priceUsd: prices.length > 0 ? Math.min(...prices) / 100 : null,
      bookingUrl: `https://${alias}.book.teeitup.com/?course=${facilityId}&date=${date}`,
      lat: course.lat ?? null,
      lng: course.lng ?? null,
      address: course.address ?? null,
    });
  }
  return slots;
}

/** Offset-or-Z suffix; a naive timestamp means the Kenna shape changed. */
const AWARE_TIMESTAMP = /(?:Z|[+-]\d{2}:?\d{2})$/;

function parseWhen(teetime: Record<string, unknown>): string {
  const value = teetime.teetime;
  if (typeof value !== "string") {
    throw new ParseError(`teetime without timestamp: ${snippet(teetime)}`);
  }
  if (!AWARE_TIMESTAMP.test(value)) {
    // Never guess a timezone — a naive timestamp means the shape changed.
    throw new ParseError(`naive teetime timestamp ${JSON.stringify(value)}`);
  }
  const when = new Date(value);
  if (Number.isNaN(when.getTime())) {
    throw new ParseError(`unparseable teetime timestamp ${JSON.stringify(value)}`);
  }
  return toEasternIso(when);
}

/** Render an instant as an ISO 8601 string in America/New_York local time. */
export function toEasternIso(when: Date): string {
  const dtf = new Intl.DateTimeFormat("en-CA", {
    timeZone: EASTERN,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  const p: Record<string, string> = {};
  for (const part of dtf.formatToParts(when)) p[part.type] = part.value;
  const asUtcMs = Date.UTC(
    Number(p.year),
    Number(p.month) - 1,
    Number(p.day),
    Number(p.hour),
    Number(p.minute),
    Number(p.second),
  );
  const offsetMin = Math.round((asUtcMs - when.getTime()) / 60_000);
  const sign = offsetMin < 0 ? "-" : "+";
  const abs = Math.abs(offsetMin);
  const hh = String(Math.trunc(abs / 60)).padStart(2, "0");
  const mm = String(abs % 60).padStart(2, "0");
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}${sign}${hh}:${mm}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function snippet(obj: unknown): string {
  try {
    return (JSON.stringify(obj) ?? String(obj)).slice(0, 200);
  } catch {
    return String(obj).slice(0, 200);
  }
}
