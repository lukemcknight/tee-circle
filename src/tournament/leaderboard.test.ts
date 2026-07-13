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
      round({ a: [3, 5], b: [4, 4] }), // a wins hole1, b wins hole2 → a:1, b:1
      round({ a: [5, 5], b: [4, 4] }), // b wins both → a:0, b:2
    ];
    expect(computeTripStandings(rounds, 'skins', 'gross')).toEqual([
      { playerId: 'b', value: 3 },
      { playerId: 'a', value: 1 },
    ]);
  });
});
