import { PlayerRound, PlayerStanding, Scoring } from './types';
import { netStrokesForHole } from './handicapStrokes';

export type SkinsHoleResult =
  | { hole: number; winnerId: string; skins: number }
  | { hole: number; winnerId: null; carried: number };

export type SkinsResult = { holes: SkinsHoleResult[]; standings: PlayerStanding[] };

export function computeSkins(
  players: PlayerRound[],
  scoring: Scoring = 'net',
): SkinsResult {
  const holeNumbers = [
    ...new Set(players.flatMap((p) => p.holes.map((h) => h.hole))),
  ].sort((a, b) => a - b);

  const won: Record<string, number> = {};
  players.forEach((p) => {
    won[p.playerId] = 0;
  });

  const holes: SkinsHoleResult[] = [];
  let carry = 1; // skins at stake on the current hole (1 + any carried)

  for (const holeNum of holeNumbers) {
    const nets = players.map((p) => {
      const h = p.holes.find((x) => x.hole === holeNum);
      return {
        playerId: p.playerId,
        net: h ? netStrokesForHole(h, p.courseHandicap, scoring) : null,
      };
    });

    // live-safe: cannot fairly resolve a hole until everyone has scored it
    if (nets.some((n) => n.net == null)) break;

    const scored = nets as { playerId: string; net: number }[];
    const lowest = Math.min(...scored.map((s) => s.net));
    const winners = scored.filter((s) => s.net === lowest);

    if (winners.length === 1) {
      won[winners[0].playerId] += carry;
      holes.push({ hole: holeNum, winnerId: winners[0].playerId, skins: carry });
      carry = 1;
    } else {
      holes.push({ hole: holeNum, winnerId: null, carried: carry });
      carry += 1;
    }
  }

  const standings = players
    .map((p) => ({ playerId: p.playerId, value: won[p.playerId] }))
    .sort((a, b) => b.value - a.value);

  return { holes, standings };
}
