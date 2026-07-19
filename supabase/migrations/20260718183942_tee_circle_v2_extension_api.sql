set lock_timeout = '10s';
set statement_timeout = '5min';

-- Narrow service-role RPCs used by the Messages Edge endpoints. The bearer
-- token is hashed before it reaches Postgres; plaintext is never persisted.


create or replace function public.get_messages_bootstrap_service_v1(p_token_hash_hex text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_session public.extension_sessions%rowtype;
  v_trip public.trips%rowtype;
  v_player public.trip_players%rowtype;
  v_snapshot jsonb;
  v_data jsonb;
begin
  select * into v_session from public.extension_sessions s
  where s.token_hash = decode(p_token_hash_hex, 'hex')
    and s.revoked_at is null and s.expires_at > now()
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  select * into v_player from public.trip_players tp
  where tp.id = v_session.trip_player_id
    and tp.trip_id = v_session.trip_id
    and tp.claimed_user_id = v_session.user_id
    and tp.rsvp <> 'no';
  if not found then
    update public.extension_sessions set revoked_at = now() where id = v_session.id;
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  select * into v_trip from public.trips t where t.id = v_session.trip_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  select s.payload into v_snapshot from public.trip_leaderboard_snapshots s
  where s.trip_id = v_trip.id and s.revision = v_trip.score_revision;
  if not found then
    return tee_internal.api_error(
      v_request_id, 'leaderboard_updating', 'The latest standings are still being prepared.', true,
      v_trip.score_revision
    );
  end if;
  update public.extension_sessions set last_used_at = now() where id = v_session.id;

  select jsonb_build_object(
    'trip', jsonb_build_object(
      'id', v_trip.id,
      'publicId', v_trip.public_id,
      'ownerId', v_trip.owner_id,
      'name', v_trip.name,
      'startDate', v_trip.starts_on,
      'endDate', v_trip.ends_on,
      'timeZone', v_trip.timezone,
      'lifecycle', v_trip.status,
      'enabledFormats', v_trip.enabled_formats,
      'primaryFormat', v_trip.primary_format,
      'scoringMode', v_trip.scoring_mode,
      'scoreRevision', v_trip.score_revision,
      'isEntitled', exists (select 1 from public.trip_entitlements te where te.trip_id = v_trip.id)
    ),
    'player', jsonb_build_object(
      'id', v_player.id,
      'tripId', v_player.trip_id,
      'claimedUserId', v_player.claimed_user_id,
      'displayName', v_player.display_name,
      'role', v_player.role,
      'rsvp', case v_player.rsvp when 'yes' then 'accepted' when 'no' then 'declined' else 'pending' end,
      'handicapSnapshot', v_player.handicap_snapshot,
      'sortOrder', (
        select count(*)::integer from public.trip_players earlier
        where earlier.trip_id = v_player.trip_id
          and (earlier.created_at, earlier.id) < (v_player.created_at, v_player.id)
      )
    ),
    'rounds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'roundId', r.id,
        'publicId', r.public_id,
        'name', r.course_name,
        'status', r.trip_round_status,
        'holeCount', r.holes
      ) order by r.trip_order)
      from public.rounds r where r.trip_id = v_trip.id
    ), '[]'::jsonb),
    'snapshot', v_snapshot
  ) into v_data;
  return tee_internal.api_success(v_request_id, v_data);
exception
  when invalid_parameter_value or invalid_text_representation then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
end;
$$;

create or replace function public.record_extension_hole_score_service_v1(
  p_token_hash_hex text,
  p_round_id uuid,
  p_trip_player_id uuid,
  p_hole_number smallint,
  p_strokes smallint,
  p_penalties smallint,
  p_idempotency_key uuid,
  p_expected_score_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_session public.extension_sessions%rowtype;
  v_trip public.trips%rowtype;
  v_round_trip_id uuid;
  v_round_status text;
  v_score public.trip_hole_scores%rowtype;
  v_audit public.trip_score_audit%rowtype;
  v_previous_strokes smallint;
  v_previous_penalties smallint;
  v_revision bigint;
begin
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Score changes are temporarily unavailable.', true);
  end if;
  select * into v_session from public.extension_sessions s
  where s.token_hash = decode(p_token_hash_hex, 'hex')
    and s.revoked_at is null and s.expires_at > now()
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  if p_trip_player_id <> v_session.trip_player_id then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Messages can only score your claimed roster spot.');
  end if;
  if not exists (
    select 1 from public.trip_players tp
    where tp.id = v_session.trip_player_id
      and tp.trip_id = v_session.trip_id
      and tp.claimed_user_id = v_session.user_id
      and tp.rsvp <> 'no'
  ) then
    update public.extension_sessions set revoked_at = now() where id = v_session.id;
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;

  select * into v_audit from public.trip_score_audit a
  where a.actor_user_id = v_session.user_id and a.idempotency_key = p_idempotency_key;
  if found then
    if v_audit.round_id = p_round_id
       and v_audit.trip_player_id = p_trip_player_id
       and v_audit.hole_number = p_hole_number
       and v_audit.strokes = p_strokes
       and v_audit.penalties = p_penalties then
      return tee_internal.api_success(v_request_id, jsonb_build_object(
        'tripId', v_audit.trip_id, 'scoreId', v_audit.score_id,
        'acceptedRevision', v_audit.revision, 'idempotentReplay', true
      ));
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another score.');
  end if;

  select r.trip_id, r.trip_round_status into v_round_trip_id, v_round_status
  from public.rounds r where r.id = p_round_id;
  if not found or v_round_trip_id <> v_session.trip_id then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  select * into strict v_trip from public.trips t where t.id = v_round_trip_id for update;
  if p_expected_score_revision is not null and v_trip.score_revision <> p_expected_score_revision then
    return tee_internal.api_error(v_request_id, 'score_conflict', 'The leaderboard changed on another device.', false, v_trip.score_revision);
  end if;
  if v_trip.status <> 'live' or v_round_status <> 'live' then
    return tee_internal.api_error(v_request_id, 'scoring_closed', 'Scoring is only available for the live round.', false, v_trip.score_revision);
  end if;
  if not exists (
    select 1 from public.trip_round_players trp
    where trp.round_id = p_round_id and trp.trip_player_id = p_trip_player_id and trp.status = 'active'
  ) then
    return tee_internal.api_error(v_request_id, 'player_not_active', 'You are not active in this round.', false, v_trip.score_revision);
  end if;
  if not exists (
    select 1 from public.round_holes rh where rh.round_id = p_round_id and rh.hole_number = p_hole_number
  ) then
    return tee_internal.api_error(v_request_id, 'hole_not_found', 'That hole is not part of this round.', false, v_trip.score_revision);
  end if;

  select * into v_score from public.trip_hole_scores s
  where s.round_id = p_round_id and s.trip_player_id = p_trip_player_id and s.hole_number = p_hole_number
  for update;
  if found then
    v_previous_strokes := v_score.strokes;
    v_previous_penalties := v_score.penalties;
  end if;

  v_revision := v_trip.score_revision + 1;
  update public.trips set score_revision = v_revision where id = v_trip.id;
  insert into public.trip_hole_scores (
    trip_id, round_id, trip_player_id, hole_number, strokes, penalties,
    recorded_by_user_id, revision, idempotency_key
  ) values (
    v_trip.id, p_round_id, p_trip_player_id, p_hole_number, p_strokes, p_penalties,
    v_session.user_id, v_revision, p_idempotency_key
  )
  on conflict (round_id, trip_player_id, hole_number) do update set
    strokes = excluded.strokes,
    penalties = excluded.penalties,
    recorded_by_user_id = excluded.recorded_by_user_id,
    revision = excluded.revision,
    idempotency_key = excluded.idempotency_key
  returning * into v_score;
  insert into public.trip_score_audit (
    score_id, trip_id, round_id, trip_player_id, hole_number,
    previous_strokes, strokes, previous_penalties, penalties,
    actor_user_id, revision, idempotency_key
  ) values (
    v_score.id, v_trip.id, p_round_id, p_trip_player_id, p_hole_number,
    v_previous_strokes, p_strokes, v_previous_penalties, p_penalties,
    v_session.user_id, v_revision, p_idempotency_key
  );
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  values (v_trip.id, v_revision)
  on conflict (trip_id, revision) do update
    set status = 'pending', available_at = now(), leased_until = null;
  update public.extension_sessions set last_used_at = now() where id = v_session.id;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'scoreId', v_score.id,
    'acceptedRevision', v_revision,
    'idempotentReplay', false,
    'score', jsonb_build_object(
      'roundId', p_round_id, 'tripPlayerId', p_trip_player_id,
      'holeNumber', p_hole_number, 'strokes', p_strokes, 'penalties', p_penalties
    )
  ));
exception
  when invalid_parameter_value or invalid_text_representation then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_score', 'Strokes must be 1–30 and penalties 0–30.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'score_write_conflict', 'The score changed while it was being saved. Refresh and retry.', true);
end;
$$;

revoke all on function public.get_messages_bootstrap_service_v1(text) from public;
revoke all on function public.record_extension_hole_score_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint) from public;
grant execute on function public.get_messages_bootstrap_service_v1(text) to service_role;
grant execute on function public.record_extension_hole_score_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint) to service_role;
