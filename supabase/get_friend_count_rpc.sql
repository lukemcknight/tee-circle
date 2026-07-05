-- RPC: return the number of accepted friendships for a given user.
-- Needed because the friendships RLS policy only exposes rows the caller is
-- part of, so the client cannot aggregate another user's friend count.
-- The function returns NULL when the caller is not allowed to see the value
-- (i.e. not self and not an accepted friend), so it doubles as a visibility
-- gate for the friend-detail screen.

CREATE OR REPLACE FUNCTION public.get_friend_count(p_user_id uuid)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.friendships f
        WHERE f.status = 'accepted'
          AND ((f.user_low = auth.uid() AND f.user_high = p_user_id)
               OR (f.user_low = p_user_id AND f.user_high = auth.uid()))
      )
    THEN (
      SELECT count(*)::integer FROM public.friendships
      WHERE status = 'accepted'
        AND (user_low = p_user_id OR user_high = p_user_id)
    )
    ELSE NULL
  END;
$$;

REVOKE ALL ON FUNCTION public.get_friend_count(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_friend_count(uuid) TO authenticated;
