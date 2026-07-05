import React, { createContext, useCallback, useContext } from 'react';
import { supabase } from '../lib/supabase';
import { posthog } from '../lib/analytics';
import { CreateRoundInput, HandicapDifferential, Round, ResponseStatus, SaveScorecardInput } from '../types';
import { useAuth } from './AuthContext';
import { formatDate, formatTime } from '../utils/date';
import { calculateCourseHandicap, calculateDifferential, calculateHandicapIndex } from '../utils/handicap';

type HandicapDifferentialRow = {
  id: string;
  user_id: string;
  round_id: string | null;
  scorecard_id: string;
  holes: number;
  adjusted_gross_score: number;
  course_rating: number;
  slope_rating: number;
  differential: number;
  played_at: string;
  created_at: string | null;
};

type DataContextValue = {
  createRound: (input: CreateRoundInput) => Promise<Round | null>;
  respondToRound: (roundId: string, response: Exclude<ResponseStatus, 'pending'>) => Promise<boolean>;
  inviteFriendToRound: (roundId: string, friendId: string) => Promise<boolean>;
  deleteRound: (roundId: string) => Promise<boolean>;
  saveScorecard: (input: SaveScorecardInput) => Promise<boolean>;
};

const DataContext = createContext<DataContextValue | undefined>(undefined);

export const DataProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();

  const createRound = useCallback(
    async (input: CreateRoundInput) => {
      if (!user) return null;

      const teeTimeIso = input.teeTime.toISOString();
      const payload = {
        course_name: input.course.name,
        course_place_id: input.course.placeId ?? null,
        course_address: input.course.address ?? null,
        course_lat: input.course.lat ?? null,
        course_lng: input.course.lng ?? null,
        tee_time: teeTimeIso,
        holes: input.holes,
        created_by: user.id,
        walk_ride: input.walking ? 'walk' : 'ride',
      };

      const { data: roundRow, error } = await supabase
        .from('rounds')
        .insert(payload)
        .select(
          'id, course_name, course_place_id, course_address, course_lat, course_lng, tee_time, holes, walk_ride, status, created_by',
        )
        .maybeSingle();

      if (error || !roundRow) return null;

      // Create the creator's 'yes' response
      // Note: A database trigger also does this (see supabase/create_creator_response_trigger.sql)
      // but we do it here as a fallback in case the trigger isn't applied yet
      await supabase.from('round_responses').insert({
        round_id: roundRow.id,
        user_id: user.id,
        response: 'yes',
      });

      const holes = roundRow.holes === 9 || roundRow.holes === 18 ? roundRow.holes : 18;

      const round: Round = {
        id: roundRow.id,
        course: roundRow.course_name,
        coursePlaceId: roundRow.course_place_id ?? null,
        courseAddress: roundRow.course_address ?? null,
        courseLat: roundRow.course_lat ?? null,
        courseLng: roundRow.course_lng ?? null,
        teeTime: roundRow.tee_time,
        date: formatDate(roundRow.tee_time),
        time: formatTime(roundRow.tee_time),
        holes: holes as 9 | 18,
        walking: roundRow.walk_ride === 'walk',
        invites: [],
        locked: roundRow.status === 'locked',
        status: roundRow.status,
        createdBy: roundRow.created_by ?? null,
      };

      posthog.capture('round_created', {
        holes: round.holes,
        walking: round.walking,
        course: round.course,
      });

      return round;
    },
    [user],
  );

  const respondToRound = useCallback(
    async (roundId: string, response: Exclude<ResponseStatus, 'pending'>): Promise<boolean> => {
      if (!user) return false;

      // Try to update existing response first
      const { data: updated, error: updateError } = await supabase
        .from('round_responses')
        .update({ response })
        .eq('round_id', roundId)
        .eq('user_id', user.id)
        .select('round_id');

      if (updateError) return false;

      // If update succeeded (found a row to update), we're done
      if (updated && updated.length > 0) return true;

      // No existing row - try inserting (only works for round creator per RLS)
      const { data: inserted, error: insertError } = await supabase
        .from('round_responses')
        .insert({
          round_id: roundId,
          user_id: user.id,
          response,
        })
        .select('round_id');

      if (insertError || !inserted || inserted.length === 0) return false;

      return true;
    },
    [user],
  );

  const inviteFriendToRound = useCallback(
    async (roundId: string, friendId: string): Promise<boolean> => {
      if (!user) return false;
      const { data, error } = await supabase.rpc('invite_friend_to_round', {
        p_round_id: roundId,
        p_friend_id: friendId,
      });
      if (error) return false;
      if (data) posthog.capture('friend_invited_to_round');
      return !!data;
    },
    [user],
  );

  const deleteRound = useCallback(
    async (roundId: string) => {
      if (!user) return false;

      const { data, error } = await supabase.rpc('delete_round', { p_round_id: roundId });
      if (error || !data) return false;

      posthog.capture('round_deleted');
      return true;
    },
    [user],
  );

  const saveScorecard = useCallback(
    async (input: SaveScorecardInput) => {
      if (!user) return false;

      const [roundResult, handicapProfileResult, differentialResult] = await Promise.all([
        supabase.from('rounds').select('id, course_name, holes, tee_time').eq('id', input.roundId).maybeSingle(),
        supabase
          .from('player_handicap_profiles')
          .select('handicap_index')
          .eq('user_id', user.id)
          .maybeSingle(),
        supabase
          .from('handicap_differentials')
          .select(
            'id, user_id, round_id, scorecard_id, holes, adjusted_gross_score, course_rating, slope_rating, differential, played_at, created_at',
          )
          .eq('user_id', user.id)
          .order('played_at', { ascending: false })
          .limit(20),
      ]);

      if (roundResult.error || !roundResult.data) return false;

      const holes = roundResult.data.holes === 9 ? 9 : 18;
      const handicapIndex = handicapProfileResult.data?.handicap_index ?? null;
      const courseHandicap =
        handicapIndex === null
          ? 0
          : calculateCourseHandicap({
              handicapIndex,
              slopeRating: input.slopeRating,
              courseRating: input.courseRating,
              par: input.par,
            });
      const netScore = input.grossScore - courseHandicap;
      const completedAt = new Date().toISOString();

      const { data: scorecardRow, error: scorecardError } = await supabase
        .from('scorecards')
        .upsert(
          {
            round_id: input.roundId,
            player_id: user.id,
            entered_by: user.id,
            status: 'completed',
            holes,
            gross_score: input.grossScore,
            net_score: netScore,
            handicap_index_at_round: handicapIndex,
            course_handicap: courseHandicap,
            playing_handicap: courseHandicap,
            course_name: roundResult.data.course_name,
            tee_name: input.teeName?.trim() || null,
            tee_color: input.teeColor?.trim() || null,
            course_rating: input.courseRating,
            slope_rating: input.slopeRating,
            par: input.par,
            completed_at: completedAt,
          },
          { onConflict: 'round_id,player_id' },
        )
        .select('id')
        .maybeSingle();

      if (scorecardError || !scorecardRow) return false;

      const differentialValue = calculateDifferential({
        grossScore: input.grossScore,
        courseRating: input.courseRating,
        slopeRating: input.slopeRating,
      });

      const { error: differentialUpsertError } = await supabase.from('handicap_differentials').upsert(
        {
          user_id: user.id,
          round_id: input.roundId,
          scorecard_id: scorecardRow.id,
          holes,
          adjusted_gross_score: input.grossScore,
          course_rating: input.courseRating,
          slope_rating: input.slopeRating,
          differential: differentialValue,
          played_at: roundResult.data.tee_time,
        },
        { onConflict: 'scorecard_id' },
      );

      if (differentialUpsertError) return false;

      const existingDifferentials: HandicapDifferential[] =
        ((differentialResult.data as HandicapDifferentialRow[] | null) ?? []).map((row) => ({
          id: row.id,
          userId: row.user_id,
          roundId: row.round_id,
          scorecardId: row.scorecard_id,
          holes: row.holes === 9 ? 9 : 18,
          adjustedGrossScore: row.adjusted_gross_score,
          courseRating: row.course_rating,
          slopeRating: row.slope_rating,
          differential: row.differential,
          playedAt: row.played_at,
          createdAt: row.created_at,
        }));

      const nextDifferentials: HandicapDifferential[] = [
        {
          id: scorecardRow.id,
          userId: user.id,
          roundId: input.roundId,
          scorecardId: scorecardRow.id,
          holes: holes as 9 | 18,
          adjustedGrossScore: input.grossScore,
          courseRating: input.courseRating,
          slopeRating: input.slopeRating,
          differential: differentialValue,
          playedAt: roundResult.data.tee_time,
          createdAt: completedAt,
        },
        ...existingDifferentials.filter((row) => row.scorecardId !== scorecardRow.id),
      ].slice(0, 20);

      const nextHandicapIndex = calculateHandicapIndex(nextDifferentials);

      const { error: handicapProfileError } = await supabase.from('player_handicap_profiles').upsert({
        user_id: user.id,
        handicap_index: nextHandicapIndex,
        rounds_count: nextDifferentials.length,
        last_calculated_at: completedAt,
      });

      if (handicapProfileError) return false;

      posthog.capture('score_posted', {
        gross_score: input.grossScore,
        holes: roundResult.data?.holes ?? null,
      });

      return true;
    },
    [user],
  );

  const value: DataContextValue = {
    createRound,
    respondToRound,
    inviteFriendToRound,
    deleteRound,
    saveScorecard,
  };

  return <DataContext.Provider value={value}>{children}</DataContext.Provider>;
};

export const useData = (): DataContextValue => {
  const ctx = useContext(DataContext);
  if (!ctx) throw new Error('useData must be used within DataProvider');
  return ctx;
};
