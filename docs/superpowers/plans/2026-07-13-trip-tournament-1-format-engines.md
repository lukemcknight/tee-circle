# Trip Tournament — Plan 1 of 3: Format Engines

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure, unit-tested TypeScript scoring engines (skins + Stableford) and a trip aggregator — the trustworthy core the whole tournament feature runs on.

**Architecture:** All scoring is pure functions in `src/tournament/`, with zero React Native / Supabase imports, consuming DB-decoupled input types. They are unit-tested with jest (jest-expo preset). The app layer (Plans 2–3) maps `scorecard_holes` rows into these input types and renders the output — but that is out of scope here.

**Tech Stack:** TypeScript, jest + jest-expo.

**Spec:** `docs/superpowers/specs/2026-07-13-teecircle-trip-tournament-design.md`

**Plan series:** (1) format engines ← this doc · (2) trip data model + build UI + live leaderboard · (3) IAP unlock + entitlement. Plans 2–3 are written after this one executes.

## Global Constraints

- Engines are PURE: no imports from `react-native`, `expo-*`, or `../lib/supabase`. Input is the DB-decoupled types in `src/tournament/types.ts`.
- Scoring supports `'net'` (default) and `'gross'`. Net uses standard stroke allocation by stroke index.
- Skins: each hole worth 1 skin; a strict-lowest score wins the hole plus any carried skins; ties carry the pot to the next hole. Holes resolve in ascending order; resolution stops at the first hole not every player has scored (live-safe).
- Stableford (standard): per hole by net-score-minus-par → albatross+ 5, eagle 4, birdie 3, par 2, bogey 1, double-or-worse 0.
- Every commit ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Jest test harness

**Files:**
- Modify: `package.json` (devDeps + `test` script + jest preset)
- Create: `babel.config.js`
- Create: `src/tournament/smoke.test.ts` (deleted at end of task)

**Interfaces:**
- Consumes: nothing.
- Produces: a working `npm test` running jest with the jest-expo preset.

- [ ] **Step 1: Install jest**

Run: `npm install --save-dev jest-expo jest @types/jest`
Expected: the three packages appear under `devDependencies` in `package.json`. (If the jest-expo preset later errors on version mismatch, align it to the SDK with `npx expo install jest-expo`.)

- [ ] **Step 2: Add babel config (jest transforms need it)**

Create `babel.config.js`:

```js
module.exports = function (api) {
  api.cache(true);
  return { presets: ['babel-preset-expo'] };
};
```

- [ ] **Step 3: Add the jest preset + test script**

In `package.json`, add to `"scripts"`: `"test": "jest"`, and add a top-level block:

```json
"jest": {
  "preset": "jest-expo",
  "testMatch": ["**/src/tournament/**/*.test.ts"]
}
```

- [ ] **Step 4: Write a smoke test**

Create `src/tournament/smoke.test.ts`:

```ts
describe('jest harness', () => {
  it('runs', () => {
    expect(1 + 1).toBe(2);
  });
});
```

- [ ] **Step 5: Run it**

Run: `npm test`
Expected: PASS — 1 test.

- [ ] **Step 6: Delete the smoke test and commit**

```bash
rm src/tournament/smoke.test.ts
git add package.json babel.config.js
git commit -m "Add jest-expo test harness

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Shared types + handicap-stroke allocation

**Files:**
- Create: `src/tournament/types.ts`
- Create: `src/tournament/handicapStrokes.ts`
- Test: `src/tournament/handicapStrokes.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `type HoleScore = { hole: number; par: number; strokeIndex: number; strokes: number | null }`
  - `type PlayerRound = { playerId: string; courseHandicap: number; holes: HoleScore[] }`
  - `type Scoring = 'net' | 'gross'`
  - `type PlayerStanding = { playerId: string; value: number }`
  - `strokesReceivedOnHole(strokeIndex: number, courseHandicap: number): number`
  - `netStrokesForHole(hole: HoleScore, courseHandicap: number, scoring: Scoring): number | null`

- [ ] **Step 1: Write the failing test**

Create `src/tournament/handicapStrokes.test.ts`:

```ts
import { strokesReceivedOnHole, netStrokesForHole } from './handicapStrokes';
import { HoleScore } from './types';

describe('strokesReceivedOnHole', () => {
  it('gives no strokes at handicap 0', () => {
    expect(strokesReceivedOnHole(1, 0)).toBe(0);
  });
  it('gives one stroke on holes with stroke index <= handicap', () => {
    expect(strokesReceivedOnHole(5, 9)).toBe(1);
    expect(strokesReceivedOnHole(10, 9)).toBe(0);
  });
  it('gives two strokes on the hardest holes for handicaps over 18', () => {
    expect(strokesReceivedOnHole(1, 20)).toBe(2); // 1 + (SI 1..2 get a second)
    expect(strokesReceivedOnHole(3, 20)).toBe(1);
  });
});

describe('netStrokesForHole', () => {
  const hole: HoleScore = { hole: 1, par: 4, strokeIndex: 5, strokes: 6 };
  it('returns gross unchanged when scoring is gross', () => {
    expect(netStrokesForHole(hole, 9, 'gross')).toBe(6);
  });
  it('subtracts received strokes when scoring is net', () => {
    expect(netStrokesForHole(hole, 9, 'net')).toBe(5); // SI5 <= 9 → 1 stroke
  });
  it('returns null for an unplayed hole', () => {
    expect(netStrokesForHole({ ...hole, strokes: null }, 9, 'net')).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm test -- handicapStrokes`
Expected: FAIL — cannot find module `./handicapStrokes`.

- [ ] **Step 3: Implement types + helper**

Create `src/tournament/types.ts`:

```ts
export type HoleScore = {
  hole: number;
  par: number;
  strokeIndex: number; // 1..18, hardest = 1
  strokes: number | null; // null = not yet played
};

export type PlayerRound = {
  playerId: string;
  courseHandicap: number;
  holes: HoleScore[];
};

export type Scoring = 'net' | 'gross';

export type PlayerStanding = { playerId: string; value: number };
```

Create `src/tournament/handicapStrokes.ts`:

```ts
import { HoleScore, Scoring } from './types';

// Standard allocation: floor(H/18) strokes on every hole, plus one more on the
// (H mod 18) hardest holes (stroke index 1..remainder).
export function strokesReceivedOnHole(
  strokeIndex: number,
  courseHandicap: number,
): number {
  if (courseHandicap <= 0) return 0;
  const base = Math.floor(courseHandicap / 18);
  const remainder = courseHandicap % 18;
  return base + (strokeIndex <= remainder ? 1 : 0);
}

export function netStrokesForHole(
  hole: HoleScore,
  courseHandicap: number,
  scoring: Scoring,
): number | null {
  if (hole.strokes == null) return null;
  if (scoring === 'gross') return hole.strokes;
  return hole.strokes - strokesReceivedOnHole(hole.strokeIndex, courseHandicap);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npm test -- handicapStrokes`
Expected: PASS — 6 assertions across the describes.

- [ ] **Step 5: Commit**

```bash
git add src/tournament/types.ts src/tournament/handicapStrokes.ts src/tournament/handicapStrokes.test.ts
git commit -m "Add tournament types and handicap-stroke allocation

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Stableford engine

**Files:**
- Create: `src/tournament/stableford.ts`
- Test: `src/tournament/stableford.test.ts`

**Interfaces:**
- Consumes: `PlayerRound`, `Scoring`, `PlayerStanding` (types.ts); `netStrokesForHole` (handicapStrokes.ts).
- Produces:
  - `stablefordPointsForHole(netStrokes: number | null, par: number): number`
  - `computeStableford(players: PlayerRound[], scoring?: Scoring): PlayerStanding[]` (sorted desc by value)

- [ ] **Step 1: Write the failing test**

Create `src/tournament/stableford.test.ts`:

```ts
import { stablefordPointsForHole, computeStableford } from './stableford';
import { PlayerRound } from './types';

describe('stablefordPointsForHole', () => {
  it('scores the standard ladder off par 4', () => {
    expect(stablefordPointsForHole(1, 4)).toBe(5); // albatross
    expect(stablefordPointsForHole(2, 4)).toBe(4); // eagle
    expect(stablefordPointsForHole(3, 4)).toBe(3); // birdie
    expect(stablefordPointsForHole(4, 4)).toBe(2); // par
    expect(stablefordPointsForHole(5, 4)).toBe(1); // bogey
    expect(stablefordPointsForHole(6, 4)).toBe(0); // double
    expect(stablefordPointsForHole(9, 4)).toBe(0); // worse
  });
  it('scores unplayed holes as zero', () => {
    expect(stablefordPointsForHole(null, 4)).toBe(0);
  });
});

describe('computeStableford', () => {
  const holes = (strokes: number[]) =>
    strokes.map((s, i) => ({ hole: i + 1, par: 4, strokeIndex: i + 1, strokes: s }));

  it('totals net points and sorts winners first', () => {
    const players: PlayerRound[] = [
      { playerId: 'a', courseHandicap: 0, holes: holes([4, 4, 3]) }, // 2+2+3 = 7
      { playerId: 'b', courseHandicap: 0, holes: holes([5, 5, 5]) }, // 1+1+1 = 3
    ];
    const result = computeStableford(players, 'net');
    expect(result).toEqual([
      { playerId: 'a', value: 7 },
      { playerId: 'b', value: 3 },
    ]);
  });

  it('applies handicap strokes in net mode', () => {
    // player b gets a stroke on SI1 (hcp 1): gross 5 → net 4 → par → 2 pts on hole 1
    const players: PlayerRound[] = [
      { playerId: 'b', courseHandicap: 1, holes: holes([5]) },
    ];
    expect(computeStableford(players, 'net')[0].value).toBe(2);
    expect(computeStableford(players, 'gross')[0].value).toBe(1); // gross bogey
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm test -- stableford`
Expected: FAIL — cannot find module `./stableford`.

- [ ] **Step 3: Implement**

Create `src/tournament/stableford.ts`:

```ts
import { PlayerRound, PlayerStanding, Scoring } from './types';
import { netStrokesForHole } from './handicapStrokes';

export function stablefordPointsForHole(
  netStrokes: number | null,
  par: number,
): number {
  if (netStrokes == null) return 0;
  const diff = netStrokes - par;
  if (diff <= -3) return 5;
  if (diff === -2) return 4;
  if (diff === -1) return 3;
  if (diff === 0) return 2;
  if (diff === 1) return 1;
  return 0;
}

export function computeStableford(
  players: PlayerRound[],
  scoring: Scoring = 'net',
): PlayerStanding[] {
  return players
    .map((p) => ({
      playerId: p.playerId,
      value: p.holes.reduce(
        (sum, h) =>
          sum +
          stablefordPointsForHole(
            netStrokesForHole(h, p.courseHandicap, scoring),
            h.par,
          ),
        0,
      ),
    }))
    .sort((a, b) => b.value - a.value);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npm test -- stableford`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/tournament/stableford.ts src/tournament/stableford.test.ts
git commit -m "Add Stableford scoring engine

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Skins engine (with carryover)

**Files:**
- Create: `src/tournament/skins.ts`
- Test: `src/tournament/skins.test.ts`

**Interfaces:**
- Consumes: `PlayerRound`, `Scoring` (types.ts); `netStrokesForHole` (handicapStrokes.ts).
- Produces:
  - `type SkinsHoleResult = { hole: number; winnerId: string; skins: number } | { hole: number; winnerId: null; carried: number }`
  - `type SkinsResult = { holes: SkinsHoleResult[]; standings: PlayerStanding[] }`
  - `computeSkins(players: PlayerRound[], scoring?: Scoring): SkinsResult` — resolves holes in ascending order, stopping at the first hole not every player has scored.

- [ ] **Step 1: Write the failing test**

Create `src/tournament/skins.test.ts`:

```ts
import { computeSkins } from './skins';
import { PlayerRound } from './types';

// helper: build players from per-hole gross strokes (par 4, SI = hole no.)
const build = (perPlayer: Record<string, (number | null)[]>): PlayerRound[] =>
  Object.entries(perPlayer).map(([playerId, strokes]) => ({
    playerId,
    courseHandicap: 0,
    holes: strokes.map((s, i) => ({ hole: i + 1, par: 4, strokeIndex: i + 1, strokes: s })),
  }));

describe('computeSkins', () => {
  it('awards a hole to the strict low scorer', () => {
    const r = computeSkins(build({ a: [3, 5], b: [4, 4] }), 'gross');
    // hole1: a low → a wins 1; hole2: tie → carries
    expect(r.standings).toEqual([
      { playerId: 'a', value: 1 },
      { playerId: 'b', value: 0 },
    ]);
    expect(r.holes[1]).toEqual({ hole: 2, winnerId: null, carried: 1 });
  });

  it('carries a tied pot into the next hole', () => {
    const r = computeSkins(build({ a: [4, 3], b: [4, 5] }), 'gross');
    // hole1 tie (carry→2 on hole2); hole2 a low → a wins 2
    expect(r.standings[0]).toEqual({ playerId: 'a', value: 2 });
    expect(r.holes[1]).toEqual({ hole: 2, winnerId: 'a', skins: 2 });
  });

  it('stops resolving at the first hole not everyone has scored', () => {
    const r = computeSkins(build({ a: [3, 4], b: [4, null] }), 'gross');
    // hole1 resolves (a wins); hole2 unresolved (b has no score) → not counted
    expect(r.standings[0]).toEqual({ playerId: 'a', value: 1 });
    expect(r.holes).toHaveLength(1);
  });

  it('uses net scores when scoring is net', () => {
    // b off SI1 gets a stroke: gross 4 → net 3, beats a's gross 3? a net 3 too → tie
    const players: PlayerRound[] = [
      { playerId: 'a', courseHandicap: 0, holes: [{ hole: 1, par: 4, strokeIndex: 1, strokes: 3 }] },
      { playerId: 'b', courseHandicap: 1, holes: [{ hole: 1, par: 4, strokeIndex: 1, strokes: 4 }] },
    ];
    const r = computeSkins(players, 'net');
    expect(r.holes[0]).toEqual({ hole: 1, winnerId: null, carried: 1 });
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm test -- skins`
Expected: FAIL — cannot find module `./skins`.

- [ ] **Step 3: Implement**

Create `src/tournament/skins.ts`:

```ts
import { PlayerRound, PlayerStanding, Scoring } from './types';
import { netStrokesForHole } from './handicapStrokes';

export type SkinsHoleResult =
  | { hole: number; winnerId: string; skins: number }
  | { hole: number; winnerId: null; carried: number };

export type SkinsResult = { holes: SkinsHoleResult[]; standings: PlayerStanding[] };

export function computeSkins(
  players: PlayerRound[],
  scoring: Scoring = 'net',
): SkinsResult {
  const holeNumbers = [
    ...new Set(players.flatMap((p) => p.holes.map((h) => h.hole))),
  ].sort((a, b) => a - b);

  const won: Record<string, number> = {};
  players.forEach((p) => {
    won[p.playerId] = 0;
  });

  const holes: SkinsHoleResult[] = [];
  let carry = 1; // skins at stake on the current hole (1 + any carried)

  for (const holeNum of holeNumbers) {
    const nets = players.map((p) => {
      const h = p.holes.find((x) => x.hole === holeNum);
      return {
        playerId: p.playerId,
        net: h ? netStrokesForHole(h, p.courseHandicap, scoring) : null,
      };
    });

    // live-safe: cannot fairly resolve a hole until everyone has scored it
    if (nets.some((n) => n.net == null)) break;

    const scored = nets as { playerId: string; net: number }[];
    const lowest = Math.min(...scored.map((s) => s.net));
    const winners = scored.filter((s) => s.net === lowest);

    if (winners.length === 1) {
      won[winners[0].playerId] += carry;
      holes.push({ hole: holeNum, winnerId: winners[0].playerId, skins: carry });
      carry = 1;
    } else {
      holes.push({ hole: holeNum, winnerId: null, carried: carry });
      carry += 1;
    }
  }

  const standings = players
    .map((p) => ({ playerId: p.playerId, value: won[p.playerId] }))
    .sort((a, b) => b.value - a.value);

  return { holes, standings };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npm test -- skins`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add src/tournament/skins.ts src/tournament/skins.test.ts
git commit -m "Add skins scoring engine with carryover

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Trip aggregator (standings across rounds)

**Files:**
- Create: `src/tournament/leaderboard.ts`
- Test: `src/tournament/leaderboard.test.ts`

**Interfaces:**
- Consumes: `PlayerRound`, `PlayerStanding`, `Scoring` (types.ts); `computeStableford` (stableford.ts); `computeSkins` (skins.ts).
- Produces:
  - `type Format = 'stableford' | 'skins'`
  - `computeTripStandings(rounds: PlayerRound[][], format: Format, scoring?: Scoring): PlayerStanding[]` — sums each player's per-round value across all rounds, sorted desc. This is the function the live leaderboard (Plan 2) calls.

- [ ] **Step 1: Write the failing test**

Create `src/tournament/leaderboard.test.ts`:

```ts
import { computeTripStandings } from './leaderboard';
import { PlayerRound } from './types';

const round = (spec: Record<string, number[]>): PlayerRound[] =>
  Object.entries(spec).map(([playerId, strokes]) => ({
    playerId,
    courseHandicap: 0,
    holes: strokes.map((s, i) => ({ hole: i + 1, par: 4, strokeIndex: i + 1, strokes: s })),
  }));

describe('computeTripStandings', () => {
  it('sums Stableford points across rounds and ranks them', () => {
    const rounds = [
      round({ a: [3, 4], b: [4, 4] }), // a: 3+2=5, b: 2+2=4
      round({ a: [4, 4], b: [3, 3] }), // a: 2+2=4, b: 3+3=6
    ];
    // totals: a=9, b=10 → b first
    expect(computeTripStandings(rounds, 'stableford', 'net')).toEqual([
      { playerId: 'b', value: 10 },
      { playerId: 'a', value: 9 },
    ]);
  });

  it('sums skins won across rounds', () => {
    const rounds = [
      round({ a: [3, 5], b: [4, 4] }), // a wins hole1 → a:1
      round({ a: [5, 5], b: [4, 4] }), // b wins both → b:2
    ];
    expect(computeTripStandings(rounds, 'skins', 'gross')).toEqual([
      { playerId: 'b', value: 2 },
      { playerId: 'a', value: 1 },
    ]);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm test -- leaderboard`
Expected: FAIL — cannot find module `./leaderboard`.

- [ ] **Step 3: Implement**

Create `src/tournament/leaderboard.ts`:

```ts
import { PlayerRound, PlayerStanding, Scoring } from './types';
import { computeStableford } from './stableford';
import { computeSkins } from './skins';

export type Format = 'stableford' | 'skins';

export function computeTripStandings(
  rounds: PlayerRound[][],
  format: Format,
  scoring: Scoring = 'net',
): PlayerStanding[] {
  const totals: Record<string, number> = {};
  for (const players of rounds) {
    const standings =
      format === 'stableford'
        ? computeStableford(players, scoring)
        : computeSkins(players, scoring).standings;
    for (const s of standings) {
      totals[s.playerId] = (totals[s.playerId] ?? 0) + s.value;
    }
  }
  return Object.entries(totals)
    .map(([playerId, value]) => ({ playerId, value }))
    .sort((a, b) => b.value - a.value);
}
```

- [ ] **Step 4: Run to verify the full suite passes**

Run: `npm test`
Expected: PASS — every tournament test green.

- [ ] **Step 5: Commit**

```bash
git add src/tournament/leaderboard.ts src/tournament/leaderboard.test.ts
git commit -m "Add trip standings aggregator across rounds

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
