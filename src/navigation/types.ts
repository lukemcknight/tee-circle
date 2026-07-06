import { Round } from '../types';

/**
 * Structured tee-time search intent. Mirrors the parse-intent Edge Function
 * schema (supabase/functions/_shared/types.ts) — keep the two in sync.
 */
export type ParsedIntent = {
  /** Course the user asked for, or "local" for a generic/nearby request. */
  courseQuery: string;
  /** Resolved ISO date, YYYY-MM-DD. */
  date: string;
  /** Window start, HH:MM 24h. */
  timeStart: string;
  /** Window end, HH:MM 24h. */
  timeEnd: string;
  players: number;
  holes: 9 | 18 | null;
  needsClarification: boolean;
  confidence: number;
};

export type RootStackParamList = {
  Welcome: undefined;
  Auth: { mode?: 'login' | 'signup' } | undefined;
  Home: undefined;
  CreateRound: undefined;
  VoiceSearch: undefined;
  TeeTimeReview: { intent: ParsedIntent; transcript: string };
  TeeTimeResults: { intent: ParsedIntent };
  RoundDetail: { roundId: string; initialRound?: Round };
  RoundScore: { roundId: string; initialRound?: Round };
  InviteFriends: { roundId: string; initialRound?: Round };
  GroupDetails: { groupId: string };
  GroupMembers: { groupId: string };
  Profile: undefined;
  Friends: undefined;
  FriendDetail: { friendId: string; friendName?: string; friendHandle?: string };
  Username: undefined;
};
