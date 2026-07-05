export type ResponseStatus = 'pending' | 'yes' | 'no';

export type Profile = {
  id: string;
  full_name?: string | null;
  username?: string | null;
};

export type HandicapProfile = {
  userId: string;
  handicapIndex: number | null;
  roundsCount: number;
  lastCalculatedAt?: string | null;
  isHidden: boolean;
};

export type HandicapDifferential = {
  id: string;
  userId: string;
  roundId?: string | null;
  scorecardId: string;
  holes: 9 | 18;
  adjustedGrossScore: number;
  courseRating: number;
  slopeRating: number;
  differential: number;
  playedAt: string;
  createdAt?: string | null;
};

export type Player = {
  id: string;
  name: string;
  handle?: string | null;
};

export type PlayerStatus = Player & {
  status: ResponseStatus;
};

export type GroupMember = {
  user_id: string;
  profile: Profile | null;
};

export type Group = {
  id: string;
  name: string;
  members: GroupMember[];
};

export type CourseSelection = {
  name: string;
  placeId?: string | null;
  address?: string | null;
  lat?: number | null;
  lng?: number | null;
};

export type Round = {
  id: string;
  course: string;
  coursePlaceId?: string | null;
  courseAddress?: string | null;
  courseLat?: number | null;
  courseLng?: number | null;
  teeTime: string;
  date: string;
  time: string;
  holes: 9 | 18;
  walking: boolean;
  invites: PlayerStatus[];
  locked: boolean;
  status?: string | null;
  createdBy?: string | null;
};

export type RoundResponse = {
  id: string;
  roundId: string;
  userId: string;
  status: ResponseStatus;
  profile?: Profile | null;
};

export type Scorecard = {
  id: string;
  roundId: string;
  playerId: string;
  enteredBy: string;
  status: 'draft' | 'completed';
  holes: 9 | 18;
  grossScore: number | null;
  netScore: number | null;
  handicapIndexAtRound: number | null;
  courseHandicap: number | null;
  playingHandicap: number | null;
  courseName?: string | null;
  teeName?: string | null;
  teeColor?: string | null;
  courseRating: number | null;
  slopeRating: number | null;
  par: number | null;
  completedAt?: string | null;
  createdAt?: string | null;
  updatedAt?: string | null;
  profile?: Profile | null;
};

export type SaveScorecardInput = {
  roundId: string;
  grossScore: number;
  courseRating: number;
  slopeRating: number;
  par: number;
  teeName?: string;
  teeColor?: string;
};

export type CreateRoundInput = {
  course: CourseSelection;
  teeTime: Date;
  holes: 9 | 18;
  walking: boolean;
};

export type FriendshipStatus = 'pending' | 'accepted';

export type Friendship = {
  id: string;
  user_low: string;
  user_high: string;
  requested_by: string;
  status: FriendshipStatus;
  created_at?: string | null;
  accepted_at?: string | null;
  otherUserId: string;
  profile: Profile | null;
};
