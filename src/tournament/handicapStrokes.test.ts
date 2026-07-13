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
