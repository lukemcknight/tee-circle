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
