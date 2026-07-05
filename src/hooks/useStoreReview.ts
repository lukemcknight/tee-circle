import { useCallback } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as StoreReview from 'expo-store-review';

const STORAGE_KEY = '@tee_circle_review';
const MIN_ROUNDS_BEFORE_REVIEW = 3;
const MIN_DAYS_BETWEEN_PROMPTS = 60;

type ReviewState = {
  roundsCreated: number;
  scoresPosted: number;
  friendsInvited: number;
  lastPromptedAt: string | null;
  hasReviewed: boolean;
};

const DEFAULT_STATE: ReviewState = {
  roundsCreated: 0,
  scoresPosted: 0,
  friendsInvited: 0,
  lastPromptedAt: null,
  hasReviewed: false,
};

const getState = async (): Promise<ReviewState> => {
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  if (!raw) return DEFAULT_STATE;
  return { ...DEFAULT_STATE, ...JSON.parse(raw) };
};

const saveState = async (state: ReviewState) => {
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(state));
};

const shouldPrompt = (state: ReviewState): boolean => {
  if (state.hasReviewed) return false;

  if (state.lastPromptedAt) {
    const daysSince =
      (Date.now() - new Date(state.lastPromptedAt).getTime()) / (1000 * 60 * 60 * 24);
    if (daysSince < MIN_DAYS_BETWEEN_PROMPTS) return false;
  }

  // Prompt after creating 3+ rounds (engaged user)
  if (state.roundsCreated >= MIN_ROUNDS_BEFORE_REVIEW) return true;

  // Prompt after posting 2+ scores (committed user)
  if (state.scoresPosted >= 2) return true;

  // Prompt after inviting friends to 2+ rounds (social user)
  if (state.friendsInvited >= 2) return true;

  return false;
};

const tryRequestReview = async (state: ReviewState) => {
  if (!shouldPrompt(state)) return;

  const isAvailable = await StoreReview.isAvailableAsync();
  if (!isAvailable) return;

  state.lastPromptedAt = new Date().toISOString();
  state.hasReviewed = true;
  await saveState(state);
  await StoreReview.requestReview();
};

export const useStoreReview = () => {
  const trackRoundCreated = useCallback(async () => {
    const state = await getState();
    state.roundsCreated += 1;
    await saveState(state);
    await tryRequestReview(state);
  }, []);

  const trackScorePosted = useCallback(async () => {
    const state = await getState();
    state.scoresPosted += 1;
    await saveState(state);
    await tryRequestReview(state);
  }, []);

  const trackFriendsInvited = useCallback(async () => {
    const state = await getState();
    state.friendsInvited += 1;
    await saveState(state);
    await tryRequestReview(state);
  }, []);

  return { trackRoundCreated, trackScorePosted, trackFriendsInvited };
};
