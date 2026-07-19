set lock_timeout = '10s';
set statement_timeout = '5min';

-- Versioned native commands. All responses use the same envelope and every
-- SECURITY DEFINER function pins search_path and performs explicit auth.


create or replace function tee_internal.api_success(p_request_id uuid, p_data jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'schemaVersion', 1,
    'requestId', p_request_id,
    'data', coalesce(p_data, '{}'::jsonb)
  );
$$;

create or replace function tee_internal.api_error(
  p_request_id uuid,
  p_code text,
  p_message text,
  p_retryable boolean default false,
  p_current_revision bigint default null,
  p_details jsonb default null
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'schemaVersion', 1,
    'requestId', p_request_id,
    'error', jsonb_build_object(
      'code', p_code,
      'message', p_message,
      'retryable', p_retryable,
      'currentRevision', p_current_revision,
      'details', p_details
    )
  ));
$$;

create or replace function tee_internal.native_writes_enabled()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, tee_internal
as $$
  select coalesce((
    select rf.enabled from tee_internal.runtime_flags rf
    where rf.key = 'native_writes_enabled'
  ), false);
$$;

create or replace function tee_internal.request_hash(p_value jsonb)
returns bytea
language sql
immutable
set search_path = pg_catalog, public
as $$
  select extensions.digest(convert_to(coalesce(p_value, 'null'::jsonb)::text, 'UTF8'), 'sha256');
$$;

revoke all on function tee_internal.api_success(uuid, jsonb) from public;
revoke all on function tee_internal.api_error(uuid, text, text, boolean, bigint, jsonb) from public;
revoke all on function tee_internal.native_writes_enabled() from public;
revoke all on function tee_internal.request_hash(jsonb) from public;

create or replace function public.create_trip_v1(p_input jsonb, p_idempotency_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_hash bytea := tee_internal.request_hash(p_input);
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_formats text[];
  v_captain_name text;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object' or p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An object input and idempotency key are required.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing
  from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_trip_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  if jsonb_typeof(p_input->'enabledFormats') = 'array' then
    select array_agg(f.value order by f.ordinality)
      into v_formats
    from jsonb_array_elements_text(p_input->'enabledFormats') with ordinality as f(value, ordinality);
  else
    v_formats := array['stableford']::text[];
  end if;

  if nullif(btrim(p_input->>'name'), '') is null
     or nullif(p_input->>'startsOn', '') is null
     or nullif(p_input->>'endsOn', '') is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'name, startsOn, and endsOn are required.');
  end if;

  select coalesce(
    nullif(btrim(p_input->>'captainDisplayName'), ''),
    nullif(btrim(pr.full_name), ''),
    nullif(btrim(pr.username), ''),
    'Captain'
  ) into v_captain_name
  from (select 1) seed
  left join public.profiles pr on pr.id = v_user_id;

  insert into public.trips (
    owner_id, name, starts_on, ends_on, timezone,
    enabled_formats, primary_format, scoring_mode
  ) values (
    v_user_id,
    btrim(p_input->>'name'),
    (p_input->>'startsOn')::date,
    (p_input->>'endsOn')::date,
    coalesce(nullif(btrim(p_input->>'timezone'), ''), 'America/New_York'),
    v_formats,
    coalesce(nullif(p_input->>'primaryFormat', ''), v_formats[1]),
    coalesce(nullif(p_input->>'scoringMode', ''), 'net')
  ) returning * into v_trip;

  insert into public.trip_players (
    trip_id, claimed_user_id, display_name, role, rsvp,
    handicap_snapshot
  ) values (
    v_trip.id, v_user_id, v_captain_name, 'captain', 'yes',
    case when nullif(p_input->>'captainHandicap', '') is null
      then null else (p_input->>'captainHandicap')::numeric end
  );

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'publicId', v_trip.public_id,
    'status', v_trip.status,
    'scoreRevision', v_trip.score_revision
  ));

  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_v1', v_hash, v_response);
  return v_response;
exception
  when invalid_text_representation or datetime_field_overflow or check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'One or more trip fields are invalid.');
end;
$$;

create or replace function public.update_trip_v1(
  p_trip_id uuid,
  p_input jsonb,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_formats text[];
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can edit this trip.');
  end if;
  if v_trip.status <> 'draft' then
    return tee_internal.api_error(v_request_id, 'trip_not_editable', 'Only draft trips can change competition settings.', false, v_trip.score_revision);
  end if;
  if p_expected_updated_at is not null and v_trip.updated_at <> p_expected_updated_at then
    return tee_internal.api_error(
      v_request_id,
      'edit_conflict',
      'The trip changed on another device.',
      false,
      v_trip.score_revision,
      jsonb_build_object('updatedAt', v_trip.updated_at)
    );
  end if;

  if p_input ? 'enabledFormats' then
    if jsonb_typeof(p_input->'enabledFormats') <> 'array' then
      return tee_internal.api_error(v_request_id, 'invalid_request', 'enabledFormats must be an array.');
    end if;
    select array_agg(f.value order by f.ordinality)
      into v_formats
    from jsonb_array_elements_text(p_input->'enabledFormats') with ordinality as f(value, ordinality);
  else
    v_formats := v_trip.enabled_formats;
  end if;

  update public.trips t set
    name = case when p_input ? 'name' then btrim(p_input->>'name') else t.name end,
    starts_on = case when p_input ? 'startsOn' then (p_input->>'startsOn')::date else t.starts_on end,
    ends_on = case when p_input ? 'endsOn' then (p_input->>'endsOn')::date else t.ends_on end,
    timezone = case when p_input ? 'timezone' then btrim(p_input->>'timezone') else t.timezone end,
    enabled_formats = v_formats,
    primary_format = case when p_input ? 'primaryFormat' then p_input->>'primaryFormat' else t.primary_format end,
    scoring_mode = case when p_input ? 'scoringMode' then p_input->>'scoringMode' else t.scoring_mode end
  where t.id = p_trip_id
  returning * into v_trip;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'status', v_trip.status,
    'updatedAt', v_trip.updated_at
  ));
exception
  when invalid_text_representation or datetime_field_overflow or check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'One or more trip fields are invalid.');
end;
$$;

create or replace function public.create_course_card_v1(p_input jsonb, p_idempotency_key uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_hash bytea := tee_internal.request_hash(p_input);
  v_existing tee_internal.command_idempotency%rowtype;
  v_card public.course_cards%rowtype;
  v_hole_count integer;
  v_si_count integer;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object'
     or jsonb_typeof(p_input->'holes') <> 'array' or p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'A course card with holes and an idempotency key is required.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_course_card_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  v_hole_count := jsonb_array_length(p_input->'holes');
  if v_hole_count not in (9, 18)
     or nullif(btrim(p_input->>'name'), '') is null
     or nullif(btrim(p_input->>'courseName'), '') is null then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'Course cards require a name, course name, and exactly 9 or 18 holes.');
  end if;

  if (select count(distinct (h->>'holeNumber')::integer) from jsonb_array_elements(p_input->'holes') h) <> v_hole_count
     or exists (
       select 1 from jsonb_array_elements(p_input->'holes') h
       where (h->>'holeNumber')::integer not between 1 and v_hole_count
          or (h->>'par')::integer not between 3 and 6
     ) then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'Hole numbers must be contiguous and each par must be between 3 and 6.');
  end if;

  select count(*) into v_si_count
  from jsonb_array_elements(p_input->'holes') h
  where nullif(h->>'strokeIndex', '') is not null;
  if v_si_count not in (0, v_hole_count) then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'Stroke indexes must be supplied for every hole or omitted for every hole.');
  end if;
  if v_si_count = v_hole_count and (
    select count(distinct (h->>'strokeIndex')::integer)
    from jsonb_array_elements(p_input->'holes') h
  ) <> v_hole_count then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'Stroke indexes must be unique.');
  end if;

  insert into public.course_cards (owner_id, name, course_name, hole_count)
  values (v_user_id, btrim(p_input->>'name'), btrim(p_input->>'courseName'), v_hole_count)
  returning * into v_card;

  insert into public.course_card_holes (course_card_id, hole_number, par, stroke_index, yards)
  select
    v_card.id,
    (h->>'holeNumber')::smallint,
    (h->>'par')::smallint,
    nullif(h->>'strokeIndex', '')::smallint,
    nullif(h->>'yards', '')::smallint
  from jsonb_array_elements(p_input->'holes') h;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'courseCardId', v_card.id,
    'holeCount', v_card.hole_count,
    'updatedAt', v_card.updated_at
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_course_card_v1', v_hash, v_response);
  return v_response;
exception
  when invalid_text_representation or check_violation or not_null_violation or unique_violation then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'One or more course-card fields are invalid.');
end;
$$;

create or replace function public.add_trip_player_v1(
  p_trip_id uuid,
  p_input jsonb,
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
  v_hash bytea := tee_internal.request_hash(jsonb_build_object('tripId', p_trip_id, 'input', p_input));
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_player public.trip_players%rowtype;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null or nullif(btrim(p_input->>'displayName'), '') is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'displayName and idempotency key are required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'add_trip_player_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can edit the roster.');
  end if;
  if v_trip.status not in ('draft', 'ready') then
    return tee_internal.api_error(v_request_id, 'roster_locked', 'The roster is locked after scoring starts.', false, v_trip.score_revision);
  end if;

  insert into public.trip_players (trip_id, display_name, role, rsvp, handicap_snapshot)
  values (
    p_trip_id,
    btrim(p_input->>'displayName'),
    coalesce(nullif(p_input->>'role', ''), 'player'),
    coalesce(nullif(p_input->>'rsvp', ''), 'pending'),
    nullif(p_input->>'handicap', '')::numeric
  ) returning * into v_player;

  insert into public.trip_round_players (
    round_id, trip_player_id, course_handicap, playing_handicap, status
  )
  select r.id, v_player.id,
    case when v_player.handicap_snapshot is null then null else round(v_player.handicap_snapshot)::smallint end,
    case when v_player.handicap_snapshot is null then null else round(v_player.handicap_snapshot)::smallint end,
    'active'
  from public.rounds r where r.trip_id = p_trip_id
  on conflict (round_id, trip_player_id) do nothing;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripPlayerId', v_player.id,
    'displayName', v_player.display_name,
    'claimed', false
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'add_trip_player_v1', v_hash, v_response);
  return v_response;
exception
  when invalid_text_representation or check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'One or more player fields are invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'duplicate_player', 'That display name is already on the roster.');
end;
$$;

create or replace function public.create_trip_round_v1(
  p_trip_id uuid,
  p_input jsonb,
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
  v_hash bytea := tee_internal.request_hash(jsonb_build_object('tripId', p_trip_id, 'input', p_input));
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_card public.course_cards%rowtype;
  v_round_id uuid;
  v_round_public_id uuid;
  v_order smallint;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null or nullif(p_input->>'courseCardId', '') is null
     or nullif(p_input->>'teeTime', '') is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'courseCardId, teeTime, and idempotency key are required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_trip_round_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can add rounds.');
  end if;
  if v_trip.status <> 'draft' then
    return tee_internal.api_error(v_request_id, 'trip_not_editable', 'Rounds can only be added while the trip is a draft.');
  end if;
  select * into v_card from public.course_cards cc
  where cc.id = (p_input->>'courseCardId')::uuid
    and cc.owner_id = v_user_id and cc.archived_at is null;
  if not found then
    return tee_internal.api_error(v_request_id, 'course_card_not_found', 'Course card not found.');
  end if;
  if (select count(*) from public.course_card_holes cch where cch.course_card_id = v_card.id) <> v_card.hole_count then
    return tee_internal.api_error(v_request_id, 'course_card_incomplete', 'The course card is missing holes.');
  end if;

  select (coalesce(max(r.trip_order), 0) + 1)::smallint into v_order
  from public.rounds r where r.trip_id = p_trip_id;

  insert into public.rounds (
    course_name, tee_time, holes, walk_ride, created_by,
    trip_id, trip_order, public_id, trip_round_status, native_updated_at
  ) values (
    v_card.course_name,
    (p_input->>'teeTime')::timestamptz,
    v_card.hole_count,
    coalesce(nullif(p_input->>'walkRide', ''), 'ride'),
    v_user_id,
    p_trip_id, v_order, gen_random_uuid(), 'scheduled', now()
  ) returning id, public_id into v_round_id, v_round_public_id;

  insert into public.round_holes (round_id, hole_number, par, stroke_index, yards)
  select v_round_id, cch.hole_number, cch.par, cch.stroke_index, cch.yards
  from public.course_card_holes cch
  where cch.course_card_id = v_card.id
  order by cch.hole_number;

  insert into public.trip_round_players (
    round_id, trip_player_id, course_handicap, playing_handicap, status
  )
  select v_round_id, tp.id,
    case when tp.handicap_snapshot is null then null else round(tp.handicap_snapshot)::smallint end,
    case when tp.handicap_snapshot is null then null else round(tp.handicap_snapshot)::smallint end,
    'active'
  from public.trip_players tp
  where tp.trip_id = p_trip_id and tp.rsvp <> 'no';

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'roundId', v_round_id,
    'publicId', v_round_public_id,
    'tripOrder', v_order,
    'status', 'scheduled'
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_round_v1', v_hash, v_response);
  return v_response;
exception
  when invalid_text_representation or datetime_field_overflow or check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'One or more round fields are invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'round_conflict', 'The round conflicts with another round.', true);
end;
$$;

create or replace function public.set_round_participation_v1(
  p_round_id uuid,
  p_trip_player_id uuid,
  p_course_handicap smallint,
  p_playing_handicap smallint,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select t.* into v_trip
  from public.trips t join public.rounds r on r.trip_id = t.id
  where r.id = p_round_id for update of t;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  if tee_internal.trip_role(v_trip.id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can edit round participation.');
  end if;
  if v_trip.status <> 'draft' then
    return tee_internal.api_error(v_request_id, 'trip_not_editable', 'Round participation can only change in a draft trip.');
  end if;
  if not exists (
    select 1 from public.trip_players tp
    where tp.id = p_trip_player_id and tp.trip_id = v_trip.id
  ) then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;

  insert into public.trip_round_players (
    round_id, trip_player_id, course_handicap, playing_handicap, status
  ) values (
    p_round_id, p_trip_player_id, p_course_handicap, p_playing_handicap, p_status
  )
  on conflict (round_id, trip_player_id) do update set
    course_handicap = excluded.course_handicap,
    playing_handicap = excluded.playing_handicap,
    status = excluded.status;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'roundId', p_round_id,
    'tripPlayerId', p_trip_player_id,
    'status', p_status
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Participation values are invalid.');
end;
$$;

revoke all on function public.create_trip_v1(jsonb, uuid) from public;
revoke all on function public.update_trip_v1(uuid, jsonb, timestamptz) from public;
revoke all on function public.create_course_card_v1(jsonb, uuid) from public;
revoke all on function public.add_trip_player_v1(uuid, jsonb, uuid) from public;
revoke all on function public.create_trip_round_v1(uuid, jsonb, uuid) from public;
revoke all on function public.set_round_participation_v1(uuid, uuid, smallint, smallint, text) from public;

grant execute on function public.create_trip_v1(jsonb, uuid) to authenticated;
grant execute on function public.update_trip_v1(uuid, jsonb, timestamptz) to authenticated;
grant execute on function public.create_course_card_v1(jsonb, uuid) to authenticated;
grant execute on function public.add_trip_player_v1(uuid, jsonb, uuid) to authenticated;
grant execute on function public.create_trip_round_v1(uuid, jsonb, uuid) to authenticated;
grant execute on function public.set_round_participation_v1(uuid, uuid, smallint, smallint, text) to authenticated;
