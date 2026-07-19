set lock_timeout = '10s';
set statement_timeout = '5min';

-- Read models, invitation/session credentials, device registration, purchase
-- intents, legacy conversion, and snapshot worker service commands.


create or replace function public.get_my_trips_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_data jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select coalesce(jsonb_agg(item order by
    case item->>'status' when 'live' then 0 when 'ready' then 1 when 'draft' then 2 when 'completed' then 3 else 4 end,
    item->>'startsOn'
  ), '[]'::jsonb) into v_data
  from (
    select jsonb_build_object(
      'tripId', t.id,
      'publicId', t.public_id,
      'name', t.name,
      'startsOn', t.starts_on,
      'endsOn', t.ends_on,
      'timezone', t.timezone,
      'status', t.status,
      'primaryFormat', t.primary_format,
      'scoringMode', t.scoring_mode,
      'scoreRevision', t.score_revision,
      'isCaptain', t.owner_id = v_user_id,
      'rosterCount', (select count(*) from public.trip_players tp where tp.trip_id = t.id and tp.rsvp <> 'no'),
      'latestSnapshotRevision', (
        select max(s.revision) from public.trip_leaderboard_snapshots s where s.trip_id = t.id
      )
    ) item
    from public.trips t
    where tee_internal.is_trip_member(t.id, v_user_id)
  ) rows;
  return tee_internal.api_success(v_request_id, jsonb_build_object('trips', v_data));
end;
$$;

create or replace function public.get_trip_bootstrap_v1(p_trip_id uuid)
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
        'isCurrentUser', tp.claimed_user_id = v_user_id
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
    'isCreator', r.created_by = v_user_id,
    'canConvert', r.created_by = v_user_id
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

create or replace function public.convert_legacy_round_v1(
  p_legacy_round_id uuid,
  p_trip_name text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_request jsonb := jsonb_build_object('legacyRoundId', p_legacy_round_id, 'tripName', p_trip_name);
  v_hash bytea := tee_internal.request_hash(v_request);
  v_existing tee_internal.command_idempotency%rowtype;
  v_legacy public.rounds%rowtype;
  v_trip public.trips%rowtype;
  v_round_id uuid;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An idempotency key is required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'convert_legacy_round_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  select * into v_legacy from public.rounds r
  where r.id = p_legacy_round_id and r.trip_id is null and r.created_by = v_user_id
  for share;
  if not found then
    return tee_internal.api_error(v_request_id, 'legacy_round_not_found', 'Only the creator can convert this legacy round.');
  end if;

  insert into public.trips (
    owner_id, name, starts_on, ends_on, timezone,
    enabled_formats, primary_format, scoring_mode
  ) values (
    v_user_id,
    coalesce(nullif(btrim(p_trip_name), ''), v_legacy.course_name || ' Trip'),
    v_legacy.tee_time::date,
    v_legacy.tee_time::date,
    'America/New_York',
    array['stableford']::text[], 'stableford', 'net'
  ) returning * into v_trip;

  insert into public.trip_players (
    trip_id, claimed_user_id, display_name, role, rsvp, handicap_snapshot
  ) values (
    v_trip.id,
    v_user_id,
    coalesce(
      (select nullif(btrim(pr.full_name), '') from public.profiles pr where pr.id = v_user_id),
      (select nullif(btrim(pr.username), '') from public.profiles pr where pr.id = v_user_id),
      'Captain'
    ),
    'captain', 'yes',
    (select hp.handicap_index from public.player_handicap_profiles hp where hp.user_id = v_user_id)
  );

  with invitees as (
    select rr.user_id,
      coalesce(nullif(btrim(pr.full_name), ''), nullif(btrim(pr.username), ''), 'Player') as base_name,
      coalesce(rr.response, 'pending') as response,
      hp.handicap_index,
      row_number() over (
        partition by lower(coalesce(nullif(btrim(pr.full_name), ''), nullif(btrim(pr.username), ''), 'Player'))
        order by rr.user_id
      ) as duplicate_number,
      count(*) over (
        partition by lower(coalesce(nullif(btrim(pr.full_name), ''), nullif(btrim(pr.username), ''), 'Player'))
      ) as duplicate_count
    from public.round_responses rr
    left join public.profiles pr on pr.id = rr.user_id
    left join public.player_handicap_profiles hp on hp.user_id = rr.user_id
    where rr.round_id = p_legacy_round_id and rr.user_id <> v_user_id
  )
  insert into public.trip_players (
    trip_id, claimed_user_id, display_name, role, rsvp, handicap_snapshot
  )
  select v_trip.id, i.user_id,
    i.base_name || case when i.duplicate_count > 1 then ' ' || i.duplicate_number::text else '' end,
    'player', case when i.response in ('yes', 'no', 'pending') then i.response else 'pending' end,
    i.handicap_index
  from invitees i;

  insert into public.rounds (
    course_name, tee_time, holes, walk_ride, created_by,
    trip_id, trip_order, public_id, trip_round_status,
    legacy_source_round_id, native_updated_at
  ) values (
    v_legacy.course_name, v_legacy.tee_time, coalesce(v_legacy.holes, 18),
    v_legacy.walk_ride, v_user_id,
    v_trip.id, 1, gen_random_uuid(), 'scheduled', p_legacy_round_id, now()
  ) returning id into v_round_id;

  insert into public.trip_round_players (
    round_id, trip_player_id, course_handicap, playing_handicap, status
  )
  select v_round_id, tp.id,
    case when tp.handicap_snapshot is null then null else round(tp.handicap_snapshot)::smallint end,
    case when tp.handicap_snapshot is null then null else round(tp.handicap_snapshot)::smallint end,
    case when tp.rsvp = 'no' then 'withdrawn' else 'active' end
  from public.trip_players tp where tp.trip_id = v_trip.id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'publicId', v_trip.public_id,
    'roundId', v_round_id,
    'legacySourceRoundId', p_legacy_round_id,
    'needsCourseCard', true
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'convert_legacy_round_v1', v_hash, v_response);
  return v_response;
exception
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'legacy_conversion_conflict', 'The legacy round could not be converted because its roster contains duplicates.');
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_legacy_round', 'The legacy round does not contain valid trip data.');
end;
$$;

create or replace function public.create_trip_invite_v1(
  p_trip_id uuid,
  p_expires_at timestamptz,
  p_max_uses integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_request jsonb := jsonb_build_object('tripId', p_trip_id, 'expiresAt', p_expires_at, 'maxUses', p_max_uses);
  v_hash bytea := tee_internal.request_hash(v_request);
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_token text;
  v_invite_id uuid;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An idempotency key is required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_trip_invite_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can create an invitation.');
  end if;
  if v_trip.status not in ('ready', 'live', 'completed') then
    return tee_internal.api_error(v_request_id, 'trip_not_shareable', 'Mark the trip ready before sharing it.');
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    return tee_internal.api_error(v_request_id, 'invalid_expiration', 'Invite expiration must be in the future.');
  end if;
  if p_max_uses is not null then
    return tee_internal.api_error(v_request_id, 'unsupported_option', 'Limited-use invitations are not available in version 1.');
  end if;
  if not exists (
    select 1 from public.trip_leaderboard_snapshots s
    where s.trip_id = p_trip_id and s.revision = v_trip.score_revision
  ) then
    return tee_internal.api_error(v_request_id, 'leaderboard_updating', 'The initial standings are still being prepared.', true, v_trip.score_revision);
  end if;

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.trip_invites (
    trip_id, token_hash, created_by, expires_at, max_uses
  ) values (
    p_trip_id, extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), v_user_id, p_expires_at, p_max_uses
  ) returning id into v_invite_id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', v_invite_id,
    'inviteToken', v_token,
    'url', 'https://teecircle.app/t/' || v_token,
    'expiresAt', p_expires_at
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_invite_v1', v_hash, v_response);
  return v_response;
exception
  when check_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Invite settings are invalid.');
end;
$$;

create or replace function public.revoke_trip_invite_v1(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select i.trip_id into v_trip_id from public.trip_invites i where i.id = p_invite_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'invite_not_found', 'Invitation not found.');
  end if;
  if tee_internal.trip_role(v_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can revoke an invitation.');
  end if;
  update public.trip_invites set revoked_at = coalesce(revoked_at, now()) where id = p_invite_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object('inviteId', p_invite_id, 'revoked', true));
end;
$$;

create or replace function tee_internal.resolve_public_trip_preview(p_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_invite public.trip_invites%rowtype;
  v_trip public.trips%rowtype;
begin
  if not coalesce((select enabled from tee_internal.runtime_flags where key = 'public_previews_enabled'), false) then
    return null;
  end if;
  select * into v_invite from public.trip_invites i where i.token_hash = p_token_hash;
  if not found then return jsonb_build_object('errorCode', 'invite_unavailable'); end if;
  if v_invite.revoked_at is not null then
    return jsonb_build_object('errorCode', 'invite_revoked');
  end if;
  if v_invite.expires_at is not null and v_invite.expires_at <= now() then
    return jsonb_build_object('errorCode', 'invite_expired');
  end if;
  select * into v_trip from public.trips t where t.id = v_invite.trip_id;
  if not found or v_trip.status not in ('ready', 'live', 'completed') then
    return jsonb_build_object('errorCode', 'invite_unavailable');
  end if;

  return jsonb_build_object(
    'trip', jsonb_build_object(
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
      'rosterCount', (select count(*) from public.trip_players tp where tp.trip_id = v_trip.id and tp.rsvp <> 'no'),
      'rounds', coalesce((
        select jsonb_agg(jsonb_build_object(
          'publicId', r.public_id,
          'courseName', r.course_name,
          'teeTime', r.tee_time,
          'holeCount', r.holes,
          'status', r.trip_round_status
        ) order by r.trip_order)
        from public.rounds r where r.trip_id = v_trip.id
      ), '[]'::jsonb)
    ),
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
        'playerId', tp.id,
        'displayName', tp.display_name,
        'role', tp.role
      ) order by case tp.role when 'captain' then 0 when 'scorer' then 1 else 2 end, tp.created_at)
      from public.trip_players tp where tp.trip_id = v_trip.id and tp.rsvp <> 'no'
    ), '[]'::jsonb),
    'snapshot', (
      select s.payload from public.trip_leaderboard_snapshots s
      where s.trip_id = v_trip.id order by s.revision desc limit 1
    )
  );
end;
$$;

create or replace function tee_internal.consume_public_rate_limit_v1(
  p_subject_hash bytea,
  p_route text,
  p_limit integer default 60,
  p_window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, tee_internal
as $$
declare
  v_window timestamptz;
  v_count integer;
begin
  if p_subject_hash is null or nullif(btrim(p_route), '') is null
     or p_limit is null or p_limit not between 1 and 1000
     or p_window_seconds is null or p_window_seconds not between 10 and 3600 then
    return false;
  end if;
  v_window := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );
  insert into tee_internal.public_rate_limits (subject_hash, route, window_started_at, request_count)
  values (p_subject_hash, p_route, v_window, 1)
  on conflict (subject_hash, route, window_started_at) do update
    set request_count = tee_internal.public_rate_limits.request_count + 1
  returning request_count into v_count;
  return v_count <= p_limit;
end;
$$;

-- PostgREST exposes public by default, so Edge Functions use narrow public
-- wrappers that remain executable by service_role only.
create or replace function public.resolve_public_trip_preview_service_v1(p_token_hash_hex text)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
  select tee_internal.resolve_public_trip_preview(decode(p_token_hash_hex, 'hex'));
$$;

create or replace function public.consume_public_rate_limit_service_v1(
  p_subject_hash_hex text,
  p_route text,
  p_limit integer default 60,
  p_window_seconds integer default 60
)
returns boolean
language sql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
  select tee_internal.consume_public_rate_limit_v1(
    decode(p_subject_hash_hex, 'hex'), p_route, p_limit, p_window_seconds
  );
$$;

revoke all on function public.get_my_trips_v1() from public;
revoke all on function public.get_trip_bootstrap_v1(uuid) from public;
revoke all on function public.get_legacy_rounds_v1() from public;
revoke all on function public.convert_legacy_round_v1(uuid, text, uuid) from public;
revoke all on function public.create_trip_invite_v1(uuid, timestamptz, integer, uuid) from public;
revoke all on function public.revoke_trip_invite_v1(uuid) from public;
revoke all on function tee_internal.resolve_public_trip_preview(bytea) from public;
revoke all on function tee_internal.consume_public_rate_limit_v1(bytea, text, integer, integer) from public;
revoke all on function public.resolve_public_trip_preview_service_v1(text) from public;
revoke all on function public.consume_public_rate_limit_service_v1(text, text, integer, integer) from public;

grant execute on function public.get_my_trips_v1() to authenticated;
grant execute on function public.get_trip_bootstrap_v1(uuid) to authenticated;
grant execute on function public.get_legacy_rounds_v1() to authenticated;
grant execute on function public.convert_legacy_round_v1(uuid, text, uuid) to authenticated;
grant execute on function public.create_trip_invite_v1(uuid, timestamptz, integer, uuid) to authenticated;
grant execute on function public.revoke_trip_invite_v1(uuid) to authenticated;
grant execute on function tee_internal.resolve_public_trip_preview(bytea) to service_role;
grant execute on function tee_internal.consume_public_rate_limit_v1(bytea, text, integer, integer) to service_role;
grant execute on function public.resolve_public_trip_preview_service_v1(text) to service_role;
grant execute on function public.consume_public_rate_limit_service_v1(text, text, integer, integer) to service_role;
