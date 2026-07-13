export type HoleScore = {
  hole: number;
  par: number;
  strokeIndex: number; // 1..18, hardest = 1
  strokes: number | null; // null = not yet played
};

export type PlayerRound = {
  playerId: string;
  courseHandicap: number;
  holes: HoleScore[];
};

export type Scoring = 'net' | 'gross';

export type PlayerStanding = { playerId: string; value: number };
