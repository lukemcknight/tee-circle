import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import { HandicapDifferential, HandicapProfile } from '../types';
import { withSupabaseRetry } from '../utils/retry';

type HandicapProfileRow = {
  user_id: string;
  handicap_index: number | null;
  rounds_count: number | null;
  last_calculated_at: string | null;
  is_hidden: boolean | null;
};

type DifferentialRow = {
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

const isMissingRelationError = (error: { code?: string; message?: string } | null) =>
  !!error && (error.code === '42P01' || error.message?.toLowerCase().includes('does not exist'));

export const useHandicap = (targetUserId?: string) => {
  const { user } = useAuth();
  const userId = targetUserId ?? user?.id ?? null;
  const [profile, setProfile] = useState<HandicapProfile | null>(null);
  const [differentials, setDifferentials] = useState<HandicapDifferential[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchHandicap = useCallback(async () => {
    if (!userId) {
      setProfile(null);
      setDifferentials([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const [profileResult, diffResult] = await Promise.all([
        withSupabaseRetry(() =>
          supabase
            .from('player_handicap_profiles')
            .select('user_id, handicap_index, rounds_count, last_calculated_at, is_hidden')
            .eq('user_id', userId)
            .maybeSingle(),
        ),
        withSupabaseRetry(() =>
          supabase
            .from('handicap_differentials')
            .select(
              'id, user_id, round_id, scorecard_id, holes, adjusted_gross_score, course_rating, slope_rating, differential, played_at, created_at',
            )
            .eq('user_id', userId)
            .order('played_at', { ascending: false })
            .limit(20),
        ),
      ]);

      if (isMissingRelationError(profileResult.error) || isMissingRelationError(diffResult.error)) {
        setProfile(null);
        setDifferentials([]);
        return;
      }

      if (profileResult.error) {
        setError(profileResult.didRetry ? 'Connection failed after retries' : 'Failed to load handicap');
      }

      if (diffResult.error && !profileResult.error) {
        setError(diffResult.didRetry ? 'Connection failed after retries' : 'Failed to load handicap history');
      }

      const profileRow = profileResult.data as HandicapProfileRow | null;
      setProfile(
        profileRow
          ? {
              userId: profileRow.user_id,
              handicapIndex: profileRow.handicap_index,
              roundsCount: profileRow.rounds_count ?? 0,
              lastCalculatedAt: profileRow.last_calculated_at,
              isHidden: profileRow.is_hidden ?? false,
            }
          : null,
      );

      const rows = (diffResult.data as DifferentialRow[] | null) ?? [];
      setDifferentials(
        rows.map((row) => ({
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
        })),
      );
    } catch {
      setError('Unexpected error loading handicap');
      setProfile(null);
      setDifferentials([]);
    } finally {
      setLoading(false);
    }
  }, [userId]);

  useEffect(() => {
    fetchHandicap();
  }, [fetchHandicap]);

  return {
    profile,
    differentials,
    loading,
    error,
    refresh: fetchHandicap,
  };
};
