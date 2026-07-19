import fixtures from "../../../contracts/native-v2-scoring-fixtures.json" with {
  type: "json",
};
import {
  buildLeaderboardSnapshotV1,
  type FormatV1,
  parseTripScoringInputV1,
  type ScoringPlayerV1,
  type ScoringV1,
  stablefordPointsForHoleV1,
  strokesReceivedOnHoleV1,
  type TripScoringInputV1,
} from "./tournament-v1.ts";

function assertEquals(actual: unknown, expected: unknown, label: string): void {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(`${label}\nexpected ${right}\nreceived ${left}`);
  }
}

function input(
  rounds: ScoringPlayerV1[][],
  format: FormatV1,
  scoring: ScoringV1,
): TripScoringInputV1 {
  return {
    trip: {
      id: "00000000-0000-4000-8000-000000000001",
      publicId: "trip-fixture",
      name: "Fixture Trip",
      status: "live",
      enabledFormats: [format],
      primaryFormat: format,
      scoringMode: scoring,
      revision: 7,
    },
    rounds: rounds.map((players, index) => ({
      roundId: `round-internal-${index + 1}`,
      publicId: `round-public-${index + 1}`,
      name: `Round ${index + 1}`,
      status: index === rounds.length - 1 ? "live" : "completed",
      tripOrder: index + 1,
      holeCount: 18,
      players: players.map((player) => ({
        ...player,
        displayName: player.displayName ?? player.playerId,
      })),
    })),
  };
}

Deno.test("stroke allocation matches the shared native fixtures", () => {
  for (const fixture of fixtures.strokeAllocation) {
    assertEquals(
      strokesReceivedOnHoleV1(
        fixture.strokeIndex,
        fixture.courseHandicap,
        fixture.holeCount as 9 | 18,
      ),
      fixture.expected,
      `stroke index ${fixture.strokeIndex}, handicap ${fixture.courseHandicap}`,
    );
  }
});

Deno.test("Stableford points match the shared native fixtures", () => {
  for (const fixture of fixtures.stablefordPoints) {
    assertEquals(
      stablefordPointsForHoleV1(fixture.netStrokes, fixture.par),
      fixture.expected,
      `Stableford ${fixture.netStrokes} on par ${fixture.par}`,
    );
  }
});

Deno.test("Stableford boards match the shared native fixtures", () => {
  for (const fixture of fixtures.stablefordBoards) {
    const snapshot = buildLeaderboardSnapshotV1(
      input(
        [fixture.players as ScoringPlayerV1[]],
        "stableford",
        fixture.scoring as ScoringV1,
      ),
    );
    const actual = snapshot.boards[0].standings.map(({ playerId, value }) => ({
      playerId,
      value,
    }));
    assertEquals(actual, fixture.expected, fixture.name);
  }
});

Deno.test("Skins standings match the shared native fixtures", () => {
  for (const fixture of fixtures.skinsBoards) {
    const snapshot = buildLeaderboardSnapshotV1(
      input(
        [fixture.players as ScoringPlayerV1[]],
        "skins",
        fixture.scoring as ScoringV1,
      ),
    );
    const actual = snapshot.boards[0].standings.map(({ playerId, value }) => ({
      playerId,
      value,
    }));
    assertEquals(actual, fixture.expectedStandings, fixture.name);
  }
});

Deno.test("multi-round boards match the shared native fixtures", () => {
  for (const fixture of fixtures.tripBoards) {
    const snapshot = buildLeaderboardSnapshotV1(
      input(
        fixture.rounds as ScoringPlayerV1[][],
        fixture.format as FormatV1,
        fixture.scoring as ScoringV1,
      ),
    );
    const actual = snapshot.boards[0].standings.map(({ playerId, value }) => ({
      playerId,
      value,
    }));
    assertEquals(actual, fixture.expected, fixture.name);
    if ("expectedCarry" in fixture) {
      assertEquals(
        snapshot.boards[0].skinsCarry,
        fixture.expectedCarry,
        `${fixture.name} carry`,
      );
    }
  }
});

Deno.test("snapshot ranks ties and emits deterministic lead changes", () => {
  const scoringInput = input(
    [[
      {
        playerId: "a",
        displayName: "Alex",
        courseHandicap: 0,
        holes: [{
          hole: 1,
          par: 4,
          strokeIndex: 1,
          strokes: 4,
          penalties: 0,
        }],
      },
      {
        playerId: "b",
        displayName: "Blake",
        courseHandicap: 0,
        holes: [{
          hole: 1,
          par: 4,
          strokeIndex: 1,
          strokes: 3,
          penalties: 0,
        }],
      },
    ]],
    "stableford",
    "gross",
  );
  const previous = buildLeaderboardSnapshotV1({
    ...scoringInput,
    rounds: [{
      ...scoringInput.rounds[0],
      players: scoringInput.rounds[0].players.map((player) => ({
        ...player,
        holes: player.holes.map((hole) => ({
          ...hole,
          strokes: player.playerId === "a" ? 3 : 4,
        })),
      })),
    }],
  });
  const current = buildLeaderboardSnapshotV1(
    scoringInput,
    previous,
    new Date("2026-07-13T18:42:10.125Z"),
  );
  assertEquals(current.currentRound?.throughHole, 1, "through hole");
  assertEquals(current.moment, {
    kind: "lead_change",
    summary: "Blake took the lead through 1",
  }, "lead change");
  assertEquals(current.generatedAt, "2026-07-13T18:42:10.125Z", "timestamp");
});

Deno.test("a tied final never declares a sole winner", () => {
  const scoringInput = input(
    [[
      {
        playerId: "a",
        displayName: "Alex",
        courseHandicap: 0,
        holes: [{
          hole: 1,
          par: 4,
          strokeIndex: 1,
          strokes: 4,
          penalties: 0,
        }],
      },
      {
        playerId: "b",
        displayName: "Blake",
        courseHandicap: 0,
        holes: [{
          hole: 1,
          par: 4,
          strokeIndex: 1,
          strokes: 4,
          penalties: 0,
        }],
      },
    ]],
    "stableford",
    "gross",
  );
  scoringInput.trip.status = "completed";
  scoringInput.rounds[0].status = "completed";
  const final = buildLeaderboardSnapshotV1(scoringInput);
  assertEquals(final.boards[0].standings[0].tied, true, "leader tied");
  assertEquals(final.moment, {
    kind: "final_result",
    summary: "Fixture Trip finishes with a tie for first",
  }, "tied final moment");
});

Deno.test("scoring input requires hole count and explicit penalties", () => {
  const valid = input(
    [[{
      playerId: "a",
      displayName: "Alex",
      courseHandicap: 0,
      holes: [{
        hole: 1,
        par: 4,
        strokeIndex: 1,
        strokes: 4,
        penalties: 1,
      }],
    }]],
    "stableford",
    "gross",
  );
  assertEquals(parseTripScoringInputV1(valid) !== null, true, "valid input");
  const missingPenalties = structuredClone(valid) as unknown as Record<
    string,
    unknown
  >;
  const rounds = missingPenalties.rounds as Array<Record<string, unknown>>;
  const players = rounds[0].players as Array<Record<string, unknown>>;
  const holes = players[0].holes as Array<Record<string, unknown>>;
  delete holes[0].penalties;
  assertEquals(
    parseTripScoringInputV1(missingPenalties),
    null,
    "missing penalties",
  );
});

Deno.test("resolved skins emit an immediate broadcast moment", () => {
  const previousInput = input(
    [[
      {
        playerId: "a",
        displayName: "Alex",
        courseHandicap: 0,
        holes: [{
          hole: 1,
          par: 4,
          strokeIndex: 1,
          strokes: 4,
          penalties: 0,
        }],
      },
      {
        playerId: "b",
        displayName: "Blake",
        courseHandicap: 0,
        holes: [{
          hole: 1,
          par: 4,
          strokeIndex: 1,
          strokes: 4,
          penalties: 0,
        }],
      },
    ]],
    "skins",
    "gross",
  );
  const previous = buildLeaderboardSnapshotV1(previousInput);
  const current = buildLeaderboardSnapshotV1({
    ...previousInput,
    trip: { ...previousInput.trip, revision: 8 },
    rounds: [{
      ...previousInput.rounds[0],
      players: previousInput.rounds[0].players.map((player) => ({
        ...player,
        holes: player.holes.map((hole) => ({
          ...hole,
          strokes: player.playerId === "b" ? 3 : 4,
        })),
      })),
    }],
  }, previous);
  assertEquals(current.moment, {
    kind: "skin_won",
    summary: "Blake won a skin",
  }, "skin won moment");
});
