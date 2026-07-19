import { HoleScore, Scoring } from './types';

// Signed playing-handicap allocation. Plus handicaps give strokes back from
// the highest stroke index (18 downward, or 9 downward on a nine-hole card).
export function strokesReceivedOnHole(
  strokeIndex: number,
  courseHandicap: number,
  holeCount: 9 | 18 = 18,
): number {
  if (!Number.isInteger(strokeIndex) || strokeIndex < 1 || strokeIndex > holeCount) return 0;
  const handicap = Math.trunc(courseHandicap);
  if (handicap === 0) return 0;
  const magnitude = Math.abs(handicap);
  const base = Math.floor(magnitude / holeCount);
  const remainder = magnitude % holeCount;
  if (handicap > 0) return base + (strokeIndex <= remainder ? 1 : 0);
  const givenBack =
    base + (remainder > 0 && strokeIndex > holeCount - remainder ? 1 : 0);
  return givenBack === 0 ? 0 : -givenBack;
}

export function netStrokesForHole(
  hole: HoleScore,
  courseHandicap: number,
  scoring: Scoring,
  holeCount: 9 | 18 = 18,
): number | null {
  if (hole.strokes == null) return null;
  const gross = hole.strokes + (hole.penalties ?? 0);
  if (scoring === 'gross') return gross;
  return gross - strokesReceivedOnHole(hole.strokeIndex, courseHandicap, holeCount);
}
