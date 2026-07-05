import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ResponseStatus, RoundResponse } from '../types';
import { withSupabaseRetry } from '../utils/retry';

type RoundResponseRow = {
  round_id: string;
  user_id: string;
  response: ResponseStatus | null;
  profile: {
    id: string;
    full_name: string | null;
    username: string | null;
  } | null;
};

export const useRoundResponses = (roundId?: string) => {
  const [responses, setResponses] = useState<RoundResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchResponses = useCallback(async () => {
    if (!roundId) {
      setResponses([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await withSupabaseRetry(() =>
        supabase
          .from('round_responses')
          .select(
            `
              round_id,
              user_id,
              response,
              profile:profiles!inner!round_responses_user_id_fkey (
                id,
                full_name,
                username
              )
            `,
          )
          .eq('round_id', roundId)
      );

      if (result.error) {
        setError(result.didRetry ? 'Connection failed after retries' : 'Failed to load responses');
        setResponses([]);
        setLoading(false);
        return;
      }

      const mapped =
        (result.data as unknown as RoundResponseRow[]).map((resp) => {
          if (!resp.profile) return null;
          return {
            id: `${resp.round_id}-${resp.user_id}`,
            roundId: resp.round_id,
            userId: resp.user_id,
            status: (resp.response as ResponseStatus) || 'pending',
            profile: resp.profile,
          };
        }) ?? [];

      setResponses(mapped.filter((resp): resp is NonNullable<typeof resp> => !!resp) as RoundResponse[]);
    } catch {
      setError('Unexpected error loading responses');
      setResponses([]);
    } finally {
      setLoading(false);
    }
  }, [roundId]);

  useEffect(() => {
    fetchResponses();
  }, [fetchResponses]);

  useEffect(() => {
    if (!roundId) return;
    const channel = supabase
      .channel(`detail-round-responses-${roundId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'round_responses', filter: `round_id=eq.${roundId}` },
        () => fetchResponses(),
      );

    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roundId, fetchResponses]);

  return { responses, loading, error, refresh: fetchResponses };
};
