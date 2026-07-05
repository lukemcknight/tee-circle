import { Round } from '../types';

export type RootStackParamList = {
  Welcome: undefined;
  Auth: { mode?: 'login' | 'signup' } | undefined;
  Home: undefined;
  CreateRound: undefined;
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
