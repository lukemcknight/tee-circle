// Shared request/response types for the TeeCircle Edge Functions.

/** One bookable tee-time slot, normalized from the Kenna (TeeItUp) API. */
export interface TeeTimeSlot {
  courseId: string;
  courseName: string;
  facilityId: number;
  alias: string;
  /** ISO 8601 timestamp in America/New_York local time, e.g. "2026-07-05T08:10:00-04:00". */
  teetimeIso: string;
  holes: 9 | 18;
  backNine: boolean;
  minPlayers: number;
  maxPlayers: number;
  /** Cheapest green fee + cart in dollars, or null when Kenna returns no price. */
  priceUsd: number | null;
  bookingUrl: string;
  lat: number | null;
  lng: number | null;
  address: string | null;
}

/** Output of parse-intent (and input to search-tee-times, possibly user-edited). */
export interface ParsedIntent {
  /** Course the user asked for, or "local" for a generic/nearby request. */
  courseQuery: string;
  /** Resolved ISO date, YYYY-MM-DD. */
  date: string;
  /** Window start, HH:MM 24h. */
  timeStart: string;
  /** Window end, HH:MM 24h. */
  timeEnd: string;
  players: number;
  holes: 9 | 18 | null;
  needsClarification: boolean;
  confidence: number;
}

export interface ParseIntentRequest {
  transcript: string;
}

export interface SearchRequest {
  intent: ParsedIntent;
  /** Optional device location, used to distance-filter generic searches. */
  coords?: { lat: number; lng: number } | null;
}

export type SearchResponse =
  | { kind: "bookable"; slots: TeeTimeSlot[] }
  | { kind: "unbookable"; name: string; externalUrl: string; reason: string }
  | { kind: "unknown"; courseQuery: string }
  | { kind: "error"; message: string };
