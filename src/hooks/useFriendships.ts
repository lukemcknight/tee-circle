import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Friendship, FriendshipStatus, Profile } from '../types';
import { useAuth } from '../context/AuthContext';
import { withSupabaseRetry } from '../utils/retry';

type FriendshipRow = {
  id: string;
  user_low: string;
  user_high: string;
  requested_by: string;
  status: FriendshipStatus;
  created_at: string | null;
  accepted_at: string | null;
  user_low_profile: Profile | null;
  user_high_profile: Profile | null;
};

export const useFriendships = () => {
  const { user } = useAuth();
  const [friendships, setFriendships] = useState<Friendship[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchFriendships = useCallback(async () => {
    if (!user) {
      setFriendships([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await withSupabaseRetry(() =>
        supabase
          .from('friendships')
          .select(
            `
            id,
            user_low,
            user_high,
            requested_by,
            status,
            created_at,
            accepted_at,
            user_low_profile:profiles!friendships_user_low_fkey (
              id,
              full_name,
              username
            ),
            user_high_profile:profiles!friendships_user_high_fkey (
              id,
              full_name,
              username
            )
          `,
          )
      );

      if (result.error) {
        setError(result.didRetry ? 'Connection failed after retries' : 'Failed to load friends');
        setFriendships([]);
        return;
      }

      const rows = (result.data as unknown as FriendshipRow[]) ?? [];

      const mapped = rows.map((row) => {
        const otherUserId = row.user_low === user.id ? row.user_high : row.user_low;
        const otherProfile = row.user_low === user.id ? row.user_high_profile : row.user_low_profile;
        return {
          ...row,
          otherUserId,
          profile: otherProfile ?? null,
        };
      });

      setFriendships(mapped);
    } catch {
      setError('Unexpected error loading friends');
      setFriendships([]);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    fetchFriendships();
  }, [fetchFriendships]);

  const incoming = friendships.filter((f) => f.status === 'pending' && f.requested_by !== user?.id);
  const outgoing = friendships.filter((f) => f.status === 'pending' && f.requested_by === user?.id);
  const accepted = friendships.filter((f) => f.status === 'accepted');

  return {
    friendships,
    incoming,
    outgoing,
    accepted,
    loading,
    error,
    refresh: fetchFriendships,
  };
};
