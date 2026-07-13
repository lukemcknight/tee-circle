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
