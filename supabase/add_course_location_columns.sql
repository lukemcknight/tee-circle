-- Adds location metadata captured from Google Places when a user selects a
-- course while creating a tee time. All columns are nullable so existing rows
-- and manual-entry fallbacks continue to work.

ALTER TABLE public.rounds
  ADD COLUMN IF NOT EXISTS course_place_id text,
  ADD COLUMN IF NOT EXISTS course_address  text,
  ADD COLUMN IF NOT EXISTS course_lat      double precision,
  ADD COLUMN IF NOT EXISTS course_lng      double precision;

-- Recreate the visible_rounds view so clients receive the new columns while
-- preserving the existing visibility filter (creator OR invited) and every
-- pre-existing column. CREATE OR REPLACE can't change column order, so drop first.
DROP VIEW IF EXISTS public.visible_rounds;
CREATE VIEW public.visible_rounds AS
SELECT DISTINCT
  r.id,
  r.group_id,
  r.course_name,
  r.course_place_id,
  r.course_address,
  r.course_lat,
  r.course_lng,
  r.tee_time,
  r.holes,
  r.walk_ride,
  r.status,
  r.created_by,
  r.created_at
FROM public.rounds r
LEFT JOIN public.round_responses rr ON rr.round_id = r.id
WHERE r.created_by = auth.uid() OR rr.user_id = auth.uid();
