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
    const r = computeSkins(build({ a: [3, 4], b: [4, 4] }), 'gross');
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
