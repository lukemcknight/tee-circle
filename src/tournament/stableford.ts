import { PlayerRound, PlayerStanding, Scoring } from './types';
import { netStrokesForHole } from './handicapStrokes';

export function stablefordPointsForHole(
  netStrokes: number | null,
  par: number,
): number {
  if (netStrokes == null) return 0;
  return Math.max(0, 2 - (netStrokes - par));
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
