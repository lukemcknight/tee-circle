import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { withSupabaseRetry } from '../utils/retry';

export const useFriendCount = (userId?: string | null) => {
  const [count, setCount] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchCount = useCallback(async () => {
    if (!userId) {
      setCount(null);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    const result = await withSupabaseRetry(() =>
      supabase.rpc('get_friend_count', { p_user_id: userId }),
    );

    if (result.error) {
      setError(result.didRetry ? 'Connection failed after retries' : 'Failed to load friend count');
      setCount(null);
    } else {
      const value = result.data as unknown as number | null;
      setCount(typeof value === 'number' ? value : null);
    }

    setLoading(false);
  }, [userId]);

  useEffect(() => {
    fetchCount();
  }, [fetchCount]);

  return { count, loading, error, refresh: fetchCount };
};
