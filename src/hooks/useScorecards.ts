import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Profile, Scorecard } from '../types';
import { withSupabaseRetry } from '../utils/retry';

type ScorecardRow = {
  id: string;
  round_id: string;
  player_id: string;
  entered_by: string;
  status: 'draft' | 'completed';
  holes: number;
  gross_score: number | null;
  net_score: number | null;
  handicap_index_at_round: number | null;
  course_handicap: number | null;
  playing_handicap: number | null;
  course_name: string | null;
  tee_name: string | null;
  tee_color: string | null;
  course_rating: number | null;
  slope_rating: number | null;
  par: number | null;
  completed_at: string | null;
  created_at: string | null;
  updated_at: string | null;
};

const isMissingRelationError = (error: { code?: string; message?: string } | null) =>
  !!error && (error.code === '42P01' || error.message?.toLowerCase().includes('does not exist'));

export const useScorecards = (roundId?: string) => {
  const [scorecards, setScorecards] = useState<Scorecard[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchScorecards = useCallback(async () => {
    if (!roundId) {
      setScorecards([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await withSupabaseRetry(() =>
        supabase
          .from('scorecards')
          .select(
            'id, round_id, player_id, entered_by, status, holes, gross_score, net_score, handicap_index_at_round, course_handicap, playing_handicap, course_name, tee_name, tee_color, course_rating, slope_rating, par, completed_at, created_at, updated_at',
          )
          .eq('round_id', roundId)
          .order('updated_at', { ascending: false }),
      );

      if (isMissingRelationError(result.error)) {
        setScorecards([]);
        return;
      }

      if (result.error) {
        setError(result.didRetry ? 'Connection failed after retries' : 'Failed to load scorecards');
        setScorecards([]);
        return;
      }

      const rows = (result.data as ScorecardRow[] | null) ?? [];
      const playerIds = Array.from(new Set(rows.map((row) => row.player_id)));

      const profilesResult =
        playerIds.length > 0
          ? await withSupabaseRetry(() =>
              supabase.from('profiles').select('id, full_name, username').in('id', playerIds),
            )
          : { data: [], error: null, didRetry: false };

      if (profilesResult.error) {
        setError(profilesResult.didRetry ? 'Connection failed after retries' : 'Failed to load scorecard players');
      }

      const profilesById = new Map<string, Profile>();
      (((profilesResult.data as Profile[] | null) ?? [])).forEach((profile) => {
        profilesById.set(profile.id, profile);
      });

      setScorecards(
        rows.map((row) => ({
          id: row.id,
          roundId: row.round_id,
          playerId: row.player_id,
          enteredBy: row.entered_by,
          status: row.status,
          holes: row.holes === 9 ? 9 : 18,
          grossScore: row.gross_score,
          netScore: row.net_score,
          handicapIndexAtRound: row.handicap_index_at_round,
          courseHandicap: row.course_handicap,
          playingHandicap: row.playing_handicap,
          courseName: row.course_name,
          teeName: row.tee_name,
          teeColor: row.tee_color,
          courseRating: row.course_rating,
          slopeRating: row.slope_rating,
          par: row.par,
          completedAt: row.completed_at,
          createdAt: row.created_at,
          updatedAt: row.updated_at,
          profile: profilesById.get(row.player_id) ?? null,
        })),
      );
    } catch {
      setError('Unexpected error loading scorecards');
      setScorecards([]);
    } finally {
      setLoading(false);
    }
  }, [roundId]);

  useEffect(() => {
    fetchScorecards();
  }, [fetchScorecards]);

  useEffect(() => {
    if (!roundId) return;

    const channel = supabase
      .channel(`scorecards-${roundId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'scorecards', filter: `round_id=eq.${roundId}` },
        () => fetchScorecards(),
      );

    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roundId, fetchScorecards]);

  return {
    scorecards,
    loading,
    error,
    refresh: fetchScorecards,
  };
};
