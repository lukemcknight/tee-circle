export type FormatV1 = "stableford" | "skins";
export type ScoringV1 = "gross" | "net";

export interface ScoringHoleV1 {
  hole: number;
  par: number;
  strokeIndex: number | null;
  strokes: number | null;
  /** Played strokes exclude penalties. Penalties are added exactly once here. */
  penalties: number;
}

export interface ScoringPlayerV1 {
  playerId: string;
  displayName: string;
  /** Schema-v1 wire name retained for compatibility; this value is the
   * round's effective signed playing-handicap allocation. */
  courseHandicap: number;
  holes: ScoringHoleV1[];
}

export interface ScoringRoundV1 {
  roundId: string;
  publicId: string;
  name: string;
  status: "scheduled" | "live" | "completed";
  tripOrder: number;
  holeCount: 9 | 18;
  players: ScoringPlayerV1[];
}

export interface TripScoringInputV1 {
  trip: {
    id: string;
    publicId: string;
    name: string;
    status: "draft" | "ready" | "live" | "completed" | "archived";
    enabledFormats: FormatV1[];
    primaryFormat: FormatV1;
    scoringMode: ScoringV1;
    revision: number;
  };
  rounds: ScoringRoundV1[];
}

export interface SnapshotStandingV1 {
  playerId: string;
  displayName: string;
  rank: number;
  value: number;
  tied: boolean;
  holesPlayed: number;
}

export interface LeaderboardSnapshotV1 {
  schemaVersion: 1;
  tripId: string;
  revision: number;
  status: TripScoringInputV1["trip"]["status"];
  primaryFormat: FormatV1;
  currentRound: {
    publicId: string;
    name: string;
    throughHole: number;
  } | null;
  boards: Array<{
    format: FormatV1;
    scoring: ScoringV1;
    standings: SnapshotStandingV1[];
    skinsCarry?: number;
  }>;
  moment: { kind: string; summary: string };
  generatedAt: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseTripScoringInputV1(
  value: unknown,
): TripScoringInputV1 | null {
  if (
    !isRecord(value) || !isRecord(value.trip) || !Array.isArray(value.rounds)
  ) {
    return null;
  }
  const trip = value.trip;
  if (
    typeof trip.id !== "string" || typeof trip.publicId !== "string" ||
    typeof trip.name !== "string" || typeof trip.status !== "string" ||
    !Array.isArray(trip.enabledFormats) ||
    !trip.enabledFormats.every((format) =>
      format === "stableford" || format === "skins"
    ) ||
    (trip.primaryFormat !== "stableford" && trip.primaryFormat !== "skins") ||
    (trip.scoringMode !== "gross" && trip.scoringMode !== "net") ||
    typeof trip.revision !== "number" || !Number.isSafeInteger(trip.revision)
  ) return null;
  for (const round of value.rounds) {
    if (
      !isRecord(round) || typeof round.roundId !== "string" ||
      typeof round.publicId !== "string" || typeof round.name !== "string" ||
      !["scheduled", "live", "completed"].includes(String(round.status)) ||
      typeof round.tripOrder !== "number" ||
      (round.holeCount !== 9 && round.holeCount !== 18) ||
      !Array.isArray(round.players)
    ) return null;
    for (const player of round.players) {
      if (
        !isRecord(player) || typeof player.playerId !== "string" ||
        typeof player.displayName !== "string" ||
        typeof player.courseHandicap !== "number" ||
        !Array.isArray(player.holes)
      ) return null;
      for (const hole of player.holes) {
        if (
          !isRecord(hole) || typeof hole.hole !== "number" ||
          typeof hole.par !== "number" ||
          (hole.strokeIndex !== null && typeof hole.strokeIndex !== "number") ||
          (hole.strokeIndex !== null &&
            (!Number.isInteger(hole.strokeIndex) ||
              hole.strokeIndex < 1 || hole.strokeIndex > round.holeCount)) ||
          (hole.strokes !== null && typeof hole.strokes !== "number") ||
          typeof hole.penalties !== "number" ||
          !Number.isInteger(hole.penalties) || hole.penalties < 0
        ) return null;
      }
    }
  }
  return value as unknown as TripScoringInputV1;
}

interface StandingTotal {
  playerId: string;
  displayName: string;
  value: number;
  holesPlayed: number;
}

export function strokesReceivedOnHoleV1(
  strokeIndex: number | null,
  handicap: number,
  holeCount: 9 | 18 = 18,
): number {
  if (
    strokeIndex === null || !Number.isInteger(strokeIndex) ||
    strokeIndex < 1 || strokeIndex > holeCount
  ) return 0;
  const wholeHandicap = Math.trunc(handicap);
  if (wholeHandicap === 0) return 0;
  const magnitude = Math.abs(wholeHandicap);
  const base = Math.floor(magnitude / holeCount);
  const remainder = magnitude % holeCount;
  if (wholeHandicap > 0) {
    return base + (strokeIndex <= remainder ? 1 : 0);
  }
  // A plus handicap gives strokes back beginning at the highest stroke index
  // (18, then 17, etc.; or 9, then 8 on a nine-hole card).
  const givenBack = base +
    (remainder > 0 && strokeIndex > holeCount - remainder ? 1 : 0);
  return givenBack === 0 ? 0 : -givenBack;
}

function scoredStrokes(
  hole: ScoringHoleV1,
  handicap: number,
  scoring: ScoringV1,
  holeCount: 9 | 18,
): number | null {
  if (hole.strokes === null) return null;
  const gross = hole.strokes + (hole.penalties ?? 0);
  if (scoring === "gross") return gross;
  return gross - strokesReceivedOnHoleV1(
    hole.strokeIndex,
    handicap,
    holeCount,
  );
}

export function stablefordPointsForHoleV1(
  strokes: number | null,
  par: number,
): number {
  return strokes === null ? 0 : Math.max(0, 2 - (strokes - par));
}

function computeStableford(
  rounds: ScoringRoundV1[],
  scoring: ScoringV1,
): StandingTotal[] {
  const totals = new Map<string, StandingTotal>();
  for (const round of rounds) {
    for (const player of round.players) {
      const existing = totals.get(player.playerId) ?? {
        playerId: player.playerId,
        displayName: player.displayName,
        value: 0,
        holesPlayed: 0,
      };
      for (const hole of player.holes) {
        const value = scoredStrokes(
          hole,
          player.courseHandicap,
          scoring,
          round.holeCount,
        );
        existing.value += stablefordPointsForHoleV1(value, hole.par);
        if (hole.strokes !== null) existing.holesPlayed += 1;
      }
      totals.set(player.playerId, existing);
    }
  }
  return [...totals.values()].sort(compareStanding);
}

function computeSkins(rounds: ScoringRoundV1[], scoring: ScoringV1): {
  standings: StandingTotal[];
  carry: number;
} {
  const totals = new Map<string, StandingTotal>();
  let carry = 1;
  for (const round of rounds) {
    for (const player of round.players) {
      const existing = totals.get(player.playerId) ?? {
        playerId: player.playerId,
        displayName: player.displayName,
        value: 0,
        holesPlayed: 0,
      };
      existing.holesPlayed += player.holes.filter((hole) =>
        hole.strokes !== null
      ).length;
      totals.set(player.playerId, existing);
    }
    const holes = [
      ...new Set(
        round.players.flatMap((player) =>
          player.holes.map((hole) => hole.hole)
        ),
      ),
    ].sort((a, b) => a - b);
    for (const holeNumber of holes) {
      const values = round.players.map((player) => {
        const hole = player.holes.find((candidate) =>
          candidate.hole === holeNumber
        );
        return {
          playerId: player.playerId,
          value: hole
            ? scoredStrokes(
              hole,
              player.courseHandicap,
              scoring,
              round.holeCount,
            )
            : null,
        };
      });
      if (values.length === 0 || values.some((entry) => entry.value === null)) {
        break;
      }
      const low = Math.min(...values.map((entry) => entry.value as number));
      const winners = values.filter((entry) => entry.value === low);
      if (winners.length === 1) {
        const winner = totals.get(winners[0].playerId);
        if (winner) winner.value += carry;
        carry = 1;
      } else {
        carry += 1;
      }
    }
  }
  return {
    standings: [...totals.values()].sort(compareStanding),
    carry,
  };
}

function compareStanding(a: StandingTotal, b: StandingTotal): number {
  // Modern JavaScript sorting is stable, so returning 0 preserves roster
  // insertion order for tied totals. Rank/tied are derived separately.
  return b.value - a.value;
}

function rankStandings(totals: StandingTotal[]): SnapshotStandingV1[] {
  return totals.map((standing, index) => {
    const previous = totals[index - 1];
    const next = totals[index + 1];
    const sameAsPrevious = previous !== undefined &&
      previous.value === standing.value;
    const firstSameIndex = sameAsPrevious
      ? totals.findIndex((candidate) => candidate.value === standing.value)
      : index;
    return {
      ...standing,
      rank: firstSameIndex + 1,
      tied: sameAsPrevious ||
        (next !== undefined && next.value === standing.value),
    };
  });
}

function currentRound(rounds: ScoringRoundV1[]): ScoringRoundV1 | null {
  return rounds.find((round) => round.status === "live") ??
    [...rounds].reverse().find((round) => round.status === "completed") ??
    rounds[0] ??
    null;
}

function throughHole(round: ScoringRoundV1 | null): number {
  if (!round || round.players.length === 0) return 0;
  const holes = [
    ...new Set(
      round.players.flatMap((player) => player.holes.map((hole) => hole.hole)),
    ),
  ].sort((a, b) => a - b);
  let through = 0;
  for (const holeNumber of holes) {
    if (
      round.players.every((player) =>
        player.holes.find((hole) => hole.hole === holeNumber)?.strokes != null
      )
    ) {
      through = holeNumber;
    } else {
      break;
    }
  }
  return through;
}

export function buildLeaderboardSnapshotV1(
  input: TripScoringInputV1,
  previous: LeaderboardSnapshotV1 | null = null,
  now = new Date(),
): LeaderboardSnapshotV1 {
  const boards = input.trip.enabledFormats.map((format) => {
    if (format === "stableford") {
      return {
        format,
        scoring: input.trip.scoringMode,
        standings: rankStandings(
          computeStableford(input.rounds, input.trip.scoringMode),
        ),
      };
    }
    const skins = computeSkins(input.rounds, input.trip.scoringMode);
    return {
      format,
      scoring: input.trip.scoringMode,
      standings: rankStandings(skins.standings),
      skinsCarry: skins.carry,
    };
  });
  const activeRound = currentRound(input.rounds);
  const progress = throughHole(activeRound);
  const primary =
    boards.find((board) => board.format === input.trip.primaryFormat) ??
      boards[0];
  const leader = primary?.standings[0];
  const oldPrimary = previous?.boards.find((board) =>
    board.format === input.trip.primaryFormat
  );
  const oldLeader = oldPrimary?.standings[0];
  const skinsBoard = boards.find((board) => board.format === "skins");
  const oldSkinsBoard = previous?.boards.find((board) =>
    board.format === "skins"
  );
  const skinWinner = skinsBoard?.standings.find((standing) => {
    const oldStanding = oldSkinsBoard?.standings.find((candidate) =>
      candidate.playerId === standing.playerId
    );
    return standing.value > (oldStanding?.value ?? 0);
  });
  const oldSkinValue = skinWinner
    ? oldSkinsBoard?.standings.find((standing) =>
      standing.playerId === skinWinner.playerId
    )?.value ?? 0
    : 0;
  const roundStarted = input.trip.status === "live" && previous !== null &&
    (previous.status !== "live" ||
      previous.currentRound?.publicId !== activeRound?.publicId);

  let moment: LeaderboardSnapshotV1["moment"];
  if (input.trip.status === "completed") {
    moment = {
      kind: "final_result",
      summary: leader
        ? leader.tied
          ? `${input.trip.name} finishes with a tie for first`
          : `${leader.displayName} wins ${input.trip.name}`
        : `${input.trip.name} is final`,
    };
  } else if (roundStarted && activeRound) {
    moment = {
      kind: "round_started",
      summary: `${activeRound.name} is now live`,
    };
  } else if (skinWinner) {
    const won = skinWinner.value - oldSkinValue;
    moment = {
      kind: "skin_won",
      summary: `${skinWinner.displayName} won ${
        won === 1 ? "a skin" : `${won} skins`
      }`,
    };
  } else if (leader && oldLeader && leader.playerId !== oldLeader.playerId) {
    moment = {
      kind: "lead_change",
      summary: `${leader.displayName} took the lead${
        progress > 0 ? ` through ${progress}` : ""
      }`,
    };
  } else {
    moment = {
      kind: "score_update",
      summary: progress > 0
        ? `Standings updated through ${progress}`
        : "Standings updated",
    };
  }

  return {
    schemaVersion: 1,
    tripId: input.trip.publicId,
    revision: input.trip.revision,
    status: input.trip.status,
    primaryFormat: input.trip.primaryFormat,
    currentRound: activeRound
      ? {
        publicId: activeRound.publicId,
        name: activeRound.name,
        throughHole: progress,
      }
      : null,
    boards,
    moment,
    generatedAt: now.toISOString(),
  };
}
