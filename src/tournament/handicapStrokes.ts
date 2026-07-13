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
