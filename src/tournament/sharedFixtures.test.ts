import fixtures from '../../contracts/native-v2-scoring-fixtures.json';
import { strokesReceivedOnHole } from './handicapStrokes';
import { computeTripStandings, Format } from './leaderboard';
import { computeStableford } from './stableford';
import { PlayerRound, Scoring } from './types';

describe('shared native-v2 golden fixtures', () => {
  it('matches signed 9/18-hole allocation', () => {
    for (const fixture of fixtures.strokeAllocation) {
      expect(
        strokesReceivedOnHole(
          fixture.strokeIndex,
          fixture.courseHandicap,
          fixture.holeCount as 9 | 18,
        ),
      ).toBe(fixture.expected);
    }
  });

  it('matches Stableford boards, including additive penalties', () => {
    for (const fixture of fixtures.stablefordBoards) {
      const actual = computeStableford(
        fixture.players as PlayerRound[],
        fixture.scoring as Scoring,
      );
      expect(actual).toEqual(fixture.expected);
    }
  });

  it('matches multi-round totals, including skins carried between rounds', () => {
    for (const fixture of fixtures.tripBoards) {
      const actual = computeTripStandings(
        fixture.rounds as PlayerRound[][],
        fixture.format as Format,
        fixture.scoring as Scoring,
      );
      expect(actual).toEqual(fixture.expected);
    }
  });
});
