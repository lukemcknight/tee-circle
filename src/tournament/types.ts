export type HoleScore = {
  hole: number;
  par: number;
  strokeIndex: number; // 1..18, hardest = 1
  strokes: number | null; // null = not yet played
  penalties?: number; // additive; played strokes above exclude penalties
};

export type PlayerRound = {
  playerId: string;
  courseHandicap: number;
  holeCount?: 9 | 18;
  holes: HoleScore[];
};

export type Scoring = 'net' | 'gross';

export type PlayerStanding = { playerId: string; value: number };
