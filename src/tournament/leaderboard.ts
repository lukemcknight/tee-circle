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
  let skinsCarry = 1;
  for (const players of rounds) {
    let standings: PlayerStanding[];
    if (format === 'stableford') {
      standings = computeStableford(players, scoring);
    } else {
      const skins = computeSkins(players, scoring, skinsCarry);
      standings = skins.standings;
      skinsCarry = skins.carry;
    }
    for (const s of standings) {
      totals[s.playerId] = (totals[s.playerId] ?? 0) + s.value;
    }
  }
  return Object.entries(totals)
    .map(([playerId, value]) => ({ playerId, value }))
    .sort((a, b) => b.value - a.value);
}
