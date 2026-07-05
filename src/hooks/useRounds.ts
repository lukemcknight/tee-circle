import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ResponseStatus, Round } from '../types';
import { getProfileHandle, getProfileName } from '../utils/profile';
import { useAuth } from '../context/AuthContext';
import { formatDate, formatTime } from '../utils/date';
import { withSupabaseRetry } from '../utils/retry';

type RoundResponseRow = {
  user_id: string;
  response: ResponseStatus | null;
  profile: {
    id: string;
    full_name: string | null;
    username: string | null;
  } | null;
};

type RoundRow = {
  id: string;
  course_name: string;
  tee_time: string;
  holes: number | null;
  walk_ride: string | null;
  status: string | null;
  round_responses: RoundResponseRow[] | null;
  created_by: string | null;
};

const mapRoundRow = (row: RoundRow): Round => {
  const holes = row.holes === 9 || row.holes === 18 ? row.holes : 18;
  const walkingValue = row.walk_ride === 'walk';
  const invites =
    row.round_responses
      ?.map((resp) => {
        if (!resp.profile) return null;
        return {
          id: resp.user_id,
          name: getProfileName(resp.profile),
          handle: getProfileHandle(resp.profile),
          status: (resp.response as ResponseStatus) || 'pending',
        };
      })
      .filter((resp): resp is NonNullable<typeof resp> => !!resp) ?? [];

  return {
    id: row.id,
    course: row.course_name ?? '',
    teeTime: row.tee_time,
    date: formatDate(row.tee_time),
    time: formatTime(row.tee_time),
    holes: holes as 9 | 18,
    walking: walkingValue,
    invites,
    locked: row.status === 'locked',
    status: row.status,
    createdBy: row.created_by ?? null,
  };
};

export const useRounds = () => {
  const { user } = useAuth();
  const [rounds, setRounds] = useState<Round[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const debounceRef = useRef<NodeJS.Timeout | null>(null);

  const fetchRounds = useCallback(async () => {
    if (!user) {
      setRounds([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const selectFields = `
        id,
        course_name,
        tee_time,
        holes,
        walk_ride,
        status,
        created_by,
        round_responses:round_responses (
          user_id,
          response,
          profile:profiles!inner!round_responses_user_id_fkey (
            id,
            full_name,
            username
          )
        )
      `;

      const fetchFrom = (table: 'visible_rounds' | 'rounds') =>
        supabase.from(table).select(selectFields).order('tee_time', { ascending: true });

      // Use retry logic for the primary query
      let dataResult = await withSupabaseRetry(() => fetchFrom('visible_rounds'));

      // Fallback if the view was dropped or errors out so creators still see their rounds.
      if (dataResult.error) {
        dataResult = await withSupabaseRetry(() => fetchFrom('rounds'));
      }

      if (dataResult.error) {
        setError(dataResult.didRetry ? 'Connection failed after retries' : 'Failed to load rounds');
        setRounds([]);
        return;
      }

      if (!dataResult.data) {
        setRounds([]);
        return;
      }

      const deduped = new Map<string, RoundRow>();
      (dataResult.data as unknown as RoundRow[]).forEach((row) => {
        deduped.set(row.id, row);
      });

      const mapped = Array.from(deduped.values()).map(mapRoundRow);
      setRounds(mapped);
    } catch {
      setError('Unexpected error loading rounds');
      setRounds([]);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    fetchRounds();
  }, [fetchRounds]);

  useEffect(() => {
    if (!user) return;

    // Debounced fetch to prevent multiple rapid subscription events from triggering duplicate fetches
    const debouncedFetch = () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
      debounceRef.current = setTimeout(() => {
        fetchRounds();
      }, 300);
    };

    const roundsChannel = supabase
      .channel(`rounds-${user.id}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rounds', filter: `created_by=eq.${user.id}` },
        debouncedFetch
      );

    const responsesChannel = supabase
      .channel(`user-round-responses-${user.id}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'round_responses', filter: `user_id=eq.${user.id}` },
        debouncedFetch
      );

    roundsChannel.subscribe();
    responsesChannel.subscribe();

    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
      supabase.removeChannel(roundsChannel);
      supabase.removeChannel(responsesChannel);
    };
  }, [user, fetchRounds]);

  return {
    rounds,
    loading,
    error,
    refresh: fetchRounds,
  };
};
