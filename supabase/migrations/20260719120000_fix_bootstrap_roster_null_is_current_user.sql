set lock_timeout = '10s';
set statement_timeout = '5min';

-- Bug: JSON null isCurrentUser for unclaimed trip seats breaks the iOS
-- client's non-optional Bool decode ("Expected to decode Bool but found
-- null"). `'isCurrentUser', tp.claimed_user_id = v_user_id` yields SQL NULL
-- whenever a seat is unclaimed (claimed_user_id is null); fixed with
-- coalesce(..., false), matching the adjacent `'claimed'` field's discipline.
--
-- The roster-building body that has this bug is NOT the current
-- public.get_trip_bootstrap_v1 (that name now points at a thin wrapper,
-- last replaced in 20260718184036_tee_circle_v2_pilot_unlock_state.sql,
-- which only patches isUnlocked). 20260718184032_tee_circle_v2_release_security.sql
-- renamed the original public.get_trip_bootstrap_v1 body (created in
-- 20260718183948_tee_circle_v2_edit_delete_commands.sql) to
-- tee_internal.get_trip_bootstrap_unfiltered_v1 without altering its body,
-- so that is the live object carrying the bug today.
--
-- A same-class sweep (nullable column compared with `=` directly inside
-- jsonb_build_object) also found public.get_legacy_rounds_v1: its
-- 'isCreator'/'canConvert' fields compare public.rounds.created_by
-- (nullable per the legacy baseline contract) with `= v_user_id` and leak
-- JSON null for rounds with no recorded creator. Fixed the same way.

create or replace function tee_internal.get_trip_bootstrap_unfiltered_v1(p_trip_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_data jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if not tee_internal.is_trip_member(p_trip_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'forbidden', 'You do not have access to this trip.');
  end if;

  select jsonb_build_object(
    'trip', jsonb_build_object(
      'tripId', v_trip.id,
      'publicId', v_trip.public_id,
      'name', v_trip.name,
      'startsOn', v_trip.starts_on,
      'endsOn', v_trip.ends_on,
      'timezone', v_trip.timezone,
      'status', v_trip.status,
      'enabledFormats', v_trip.enabled_formats,
      'primaryFormat', v_trip.primary_format,
      'scoringMode', v_trip.scoring_mode,
      'scoreRevision', v_trip.score_revision,
      'isCaptain', v_trip.owner_id = v_user_id,
      'canManage', tee_internal.can_manage_trip(v_trip.id, v_user_id),
      'isUnlocked', exists (select 1 from public.trip_entitlements te where te.trip_id = v_trip.id),
      'createdAt', v_trip.created_at,
      'updatedAt', v_trip.updated_at
    ),
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tripPlayerId', tp.id,
        'displayName', tp.display_name,
        'role', tp.role,
        'rsvp', tp.rsvp,
        'handicapSnapshot', tp.handicap_snapshot,
        'claimed', tp.claimed_user_id is not null,
        'isCurrentUser', coalesce(tp.claimed_user_id = v_user_id, false),
        'updatedAt', tp.updated_at
      ) order by case tp.role when 'captain' then 0 when 'scorer' then 1 else 2 end, tp.created_at)
      from public.trip_players tp where tp.trip_id = v_trip.id
    ), '[]'::jsonb),
    'rounds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'roundId', r.id,
        'publicId', r.public_id,
        'tripOrder', r.trip_order,
        'courseName', r.course_name,
        'teeTime', r.tee_time,
        'holeCount', r.holes,
        'walkRide', r.walk_ride,
        'status', r.trip_round_status,
        'legacySourceRoundId', r.legacy_source_round_id,
        'nativeUpdatedAt', r.native_updated_at,
        'holes', coalesce((
          select jsonb_agg(jsonb_build_object(
            'holeNumber', rh.hole_number,
            'par', rh.par,
            'strokeIndex', rh.stroke_index,
            'yards', rh.yards
          ) order by rh.hole_number)
          from public.round_holes rh where rh.round_id = r.id
        ), '[]'::jsonb),
        'players', coalesce((
          select jsonb_agg(jsonb_build_object(
            'tripPlayerId', trp.trip_player_id,
            'courseHandicap', trp.course_handicap,
            'playingHandicap', trp.playing_handicap,
            'status', trp.status
          ) order by tp.display_name)
          from public.trip_round_players trp
          join public.trip_players tp on tp.id = trp.trip_player_id
          where trp.round_id = r.id
        ), '[]'::jsonb),
        'scores', coalesce((
          select jsonb_agg(jsonb_build_object(
            'scoreId', s.id,
            'tripPlayerId', s.trip_player_id,
            'holeNumber', s.hole_number,
            'strokes', s.strokes,
            'penalties', s.penalties,
            'revision', s.revision,
            'updatedAt', s.updated_at
          ) order by s.trip_player_id, s.hole_number)
          from public.trip_hole_scores s where s.round_id = r.id
        ), '[]'::jsonb)
      ) order by r.trip_order)
      from public.rounds r where r.trip_id = v_trip.id
    ), '[]'::jsonb),
    'snapshot', (
      select s.payload from public.trip_leaderboard_snapshots s
      where s.trip_id = v_trip.id order by s.revision desc limit 1
    ),
    'readinessIssues', case when v_trip.status = 'draft'
      then tee_internal.trip_readiness_issues(v_trip.id) else '[]'::jsonb end
  ) into v_data;
  return tee_internal.api_success(v_request_id, v_data);
end;
$$;

create or replace function public.get_legacy_rounds_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_rounds jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'roundId', r.id,
    'courseName', r.course_name,
    'teeTime', r.tee_time,
    'holeCount', r.holes,
    'walkRide', r.walk_ride,
    'legacyStatus', r.status,
    'isCreator', coalesce(r.created_by = v_user_id, false),
    'canConvert', coalesce(r.created_by = v_user_id, false)
  ) order by r.tee_time desc), '[]'::jsonb) into v_rounds
  from public.rounds r
  where r.trip_id is null
    and (
      r.created_by = v_user_id
      or exists (
        select 1 from public.round_responses rr
        where rr.round_id = r.id and rr.user_id = v_user_id
      )
    );
  return tee_internal.api_success(v_request_id, jsonb_build_object('rounds', v_rounds));
end;
$$;
