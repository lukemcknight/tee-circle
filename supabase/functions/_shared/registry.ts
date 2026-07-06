// Course registry — the source of truth for which courses TeeCircle can search
// and book. Adding a course is a functions deploy, not an app release.
//
// Facility ids and tenant aliases were verified against the working
// tee-time-sniper integration (config/courses.yaml, verified 2026-07-02).
// Coordinates and addresses are best-effort from public listings.

export interface BookableCourse {
  id: string;
  name: string;
  facilityId: number;
  /** TeeItUp tenant alias, sent as the x-be-alias header. */
  alias: string;
  bookable: true;
  lat: number;
  lng: number;
  address: string;
  /** Extra names users might say, for fuzzy matching. */
  aliases?: string[];
}

export interface UnbookableCourse {
  id: string;
  name: string;
  bookable: false;
  /** Why we can't book it in-app (shown to the user). */
  reason: string;
  /** Where to send the user to book on the operator's own site. */
  externalUrl: string;
  lat?: number;
  lng?: number;
  aliases?: string[];
}

export type Course = BookableCourse | UnbookableCourse;

const CRC_ALIAS = "cincinnati-recreation-commission";
const GREAT_PARKS_BOOKING = "https://reservations.greatparks.org/teetimewizard.aspx";
const GREAT_PARKS_REASON = "operator blocks automated booking (WebTrac WAF) — book on the Great Parks site";
const FAIRFIELD_URL = "https://www.fairfield-city.org/369/Golf-Courses";
const FAIRFIELD_REASON = "operator disallows automated booking (robots.txt) — book on the Fairfield Greens site";

export const COURSES: Course[] = [
  // --- Live on TeeItUp/Kenna: Cincinnati Recreation Commission (one tenant) ---
  {
    id: "avon-fields",
    name: "Avon Fields Golf Course",
    facilityId: 3265,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.152,
    lng: -84.481,
    address: "4081 Reading Rd, Cincinnati, OH 45229",
    aliases: ["avon"],
  },
  {
    id: "california",
    name: "California Golf Course",
    facilityId: 3266,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.07,
    lng: -84.426,
    address: "5924 Kellogg Ave, Cincinnati, OH 45230",
  },
  {
    id: "glenview",
    name: "Glenview Golf Course",
    facilityId: 3267,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.287,
    lng: -84.469,
    address: "10965 Springfield Pike, Cincinnati, OH 45246",
  },
  {
    id: "neumann",
    name: "Neumann Golf Course",
    facilityId: 3269,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.137,
    lng: -84.66,
    address: "7215 Bridgetown Rd, Cincinnati, OH 45248",
  },
  {
    id: "reeves",
    name: "Reeves Golf Course",
    facilityId: 3270,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.119,
    lng: -84.415,
    address: "4747 Playfield Ln, Cincinnati, OH 45226",
  },
  {
    id: "reeves-par3",
    name: "Reeves Par 3 Golf Course",
    facilityId: 18138,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.119,
    lng: -84.416,
    address: "4747 Playfield Ln, Cincinnati, OH 45226",
    aliases: ["reeves par three"],
  },
  {
    id: "woodland",
    name: "Woodland Golf Course",
    facilityId: 3278,
    alias: CRC_ALIAS,
    bookable: true,
    lat: 39.091,
    lng: -84.633,
    address: "5820 Muddy Creek Rd, Cincinnati, OH 45238",
  },

  // --- Live on TeeItUp/Kenna: independents ---
  {
    id: "beech-creek",
    name: "Beech Creek Golf Course",
    facilityId: 4405,
    alias: "beech-creek-golf-course",
    bookable: true,
    lat: 39.245,
    lng: -84.545,
    address: "1831 Hudepohl Ln, Cincinnati, OH 45231",
  },

  // --- Not bookable in-app: deep-link to the operator's own site only ---
  {
    id: "blue-ash",
    name: "Blue Ash Golf Course",
    bookable: false,
    reason: "Cloudflare-protected booking — book on the Blue Ash site",
    externalUrl: "https://blueash.cps.golf",
    lat: 39.248,
    lng: -84.388,
  },
  {
    id: "the-vineyard",
    name: "The Vineyard Golf Course",
    bookable: false,
    reason: GREAT_PARKS_REASON,
    externalUrl: GREAT_PARKS_BOOKING,
    lat: 39.064,
    lng: -84.339,
    aliases: ["vineyard"],
  },
  {
    id: "sharon-woods",
    name: "Sharon Woods Golf Course",
    bookable: false,
    reason: GREAT_PARKS_REASON,
    externalUrl: GREAT_PARKS_BOOKING,
    lat: 39.281,
    lng: -84.396,
  },
  {
    id: "miami-whitewater",
    name: "Miami Whitewater Forest Golf Course",
    bookable: false,
    reason: GREAT_PARKS_REASON,
    externalUrl: GREAT_PARKS_BOOKING,
    lat: 39.247,
    lng: -84.743,
    aliases: ["miami whitewater"],
  },
  {
    id: "the-mill",
    name: "The Mill Course",
    bookable: false,
    reason: GREAT_PARKS_REASON,
    externalUrl: GREAT_PARKS_BOOKING,
    lat: 39.254,
    lng: -84.545,
    aliases: ["mill course", "winton woods"],
  },
  {
    id: "meadow-links",
    name: "Meadow Links & Golf Academy",
    bookable: false,
    reason: GREAT_PARKS_REASON,
    externalUrl: GREAT_PARKS_BOOKING,
    lat: 39.26,
    lng: -84.568,
    aliases: ["meadow links"],
  },
  {
    id: "little-miami",
    name: "Little Miami Golf Center",
    bookable: false,
    reason: GREAT_PARKS_REASON,
    externalUrl: GREAT_PARKS_BOOKING,
    lat: 39.123,
    lng: -84.356,
    aliases: ["little miami"],
  },
  {
    id: "fairfield-south",
    name: "Fairfield Greens South Trace",
    bookable: false,
    reason: FAIRFIELD_REASON,
    externalUrl: FAIRFIELD_URL,
    lat: 39.326,
    lng: -84.523,
    aliases: ["fairfield greens", "fairfield south"],
  },
  {
    id: "fairfield-north",
    name: "Fairfield Greens North Trace",
    bookable: false,
    reason: FAIRFIELD_REASON,
    externalUrl: FAIRFIELD_URL,
    lat: 39.34,
    lng: -84.545,
    aliases: ["fairfield north"],
  },
  {
    id: "legendary-run",
    name: "Legendary Run Golf Course",
    bookable: false,
    reason: "operator blocks automated booking — book on the Legendary Run site",
    externalUrl: "https://www.legendaryrungolf.com/golf/tee-times",
    lat: 39.072,
    lng: -84.272,
    aliases: ["legendary run"],
  },
];

export function bookableCourses(): BookableCourse[] {
  return COURSES.filter((c): c is BookableCourse => c.bookable);
}

export function unbookableCourses(): UnbookableCourse[] {
  return COURSES.filter((c): c is UnbookableCourse => !c.bookable);
}

export function courseByFacilityId(
  courses: BookableCourse[],
): Map<number, BookableCourse> {
  return new Map(courses.map((c) => [c.facilityId, c]));
}

// --- Course resolution -------------------------------------------------------

const GENERIC_QUERIES = new Set([
  "",
  "local",
  "nearby",
  "near me",
  "any",
  "anywhere",
  "around here",
  "close by",
]);

/** True when the query means "any course near me" rather than a specific course. */
export function isGenericQuery(query: string): boolean {
  return GENERIC_QUERIES.has(normalize(query));
}

/** Lowercase, strip punctuation and generic golf words, collapse whitespace. */
export function normalize(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\b(golf course|golf club|golf center|golf academy|golf|course|club|gc)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  const m = a.length;
  const n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const curr = [i];
    for (let j = 1; j <= n; j++) {
      curr[j] = Math.min(
        prev[j] + 1,
        curr[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    prev = curr;
  }
  return prev[n];
}

function candidateNames(course: Course): string[] {
  return [course.name, course.id.replace(/-/g, " "), ...(course.aliases ?? [])];
}

/**
 * Fuzzy-match a spoken course query against the registry.
 * Token inclusion on name + aliases first, Levenshtein <= 2 as tiebreak.
 * Bookable courses win over unbookable ones on equal match quality.
 */
export function findCourse(query: string): Course | null {
  const q = normalize(query);
  if (!q) return null;
  const qTokens = q.split(" ");

  let best: { course: Course; score: number } | null = null;
  for (const course of COURSES) {
    let score = Infinity;
    for (const raw of candidateNames(course)) {
      const cand = normalize(raw);
      if (!cand) continue;
      const cTokens = new Set(cand.split(" "));
      if (cand === q) {
        score = Math.min(score, 0);
      } else if (qTokens.every((t) => cTokens.has(t)) || cand.includes(q)) {
        score = Math.min(score, 1);
      } else {
        const dist = levenshtein(q, cand);
        if (dist <= 2) score = Math.min(score, 2 + dist);
      }
    }
    if (score === Infinity) continue;
    if (
      best === null ||
      score < best.score ||
      (score === best.score && course.bookable && !best.course.bookable)
    ) {
      best = { course, score };
    }
  }
  return best?.course ?? null;
}

/** Great-circle distance in kilometers. */
export function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
