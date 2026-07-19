set lock_timeout = '10s';
set statement_timeout = '5min';

-- Final native edit/delete commands, account-deletion preparation, and the
-- Realtime refresh-hint publication. This remains additive to the reviewed
-- legacy baseline and does not deploy or mutate a linked project by itself.


-- Deleting a round/player must never cascade an accepted score. Commands
-- preflight this condition and the FK is the final service-role defense.
alter table public.trip_hole_scores
  drop constraint trip_hole_scores_round_player_fkey;
alter table public.trip_hole_scores
  add constraint trip_hole_scores_round_player_fkey
  foreign key (round_id, trip_player_id)
  references public.trip_round_players(round_id, trip_player_id)
  on delete restrict;

create or replace function tee_internal.enforce_course_card_hole_bounds()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_hole_count smallint;
begin
  select cc.hole_count into v_hole_count
  from public.course_cards cc where cc.id = new.course_card_id;
  if v_hole_count is null
     or new.hole_number > v_hole_count
     or (new.stroke_index is not null and new.stroke_index > v_hole_count) then
    raise exception using errcode = '23514', message = 'course_card_hole_out_of_bounds';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_course_card_hole_bounds on public.course_card_holes;
create trigger enforce_course_card_hole_bounds
before insert or update on public.course_card_holes
for each row execute function tee_internal.enforce_course_card_hole_bounds();

revoke all on function tee_internal.enforce_course_card_hole_bounds() from public;

create or replace function tee_internal.course_card_payload_v1(p_course_card_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'id', cc.id,
    'name', cc.name,
    'courseName', cc.course_name,
    'holeCount', cc.hole_count,
    'createdAt', cc.created_at,
    'updatedAt', cc.updated_at,
    'holes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'holeNumber', cch.hole_number,
        'par', cch.par,
        'strokeIndex', cch.stroke_index,
        'yards', cch.yards
      ) order by cch.hole_number)
      from public.course_card_holes cch
      where cch.course_card_id = cc.id
    ), '[]'::jsonb)
  )
  from public.course_cards cc where cc.id = p_course_card_id;
$$;

revoke all on function tee_internal.course_card_payload_v1(uuid) from public;

create or replace function public.update_course_card_v1(
  p_course_card_id uuid,
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
  v_card public.course_cards%rowtype;
  v_hole_count integer;
  v_stroke_index_count integer;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object'
     or coalesce(jsonb_typeof(p_input->'holes'), '') <> 'array'
     or nullif(btrim(p_input->>'name'), '') is null
     or nullif(btrim(p_input->>'courseName'), '') is null then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'A name, course name, and complete holes array are required.');
  end if;

  select * into v_card from public.course_cards cc
  where cc.id = p_course_card_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'course_card_not_found', 'Course card not found.');
  end if;
  if v_card.owner_id <> v_user_id then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the course-card owner can edit it.');
  end if;
  if v_card.archived_at is not null then
    return tee_internal.api_error(v_request_id, 'course_card_archived', 'Archived course cards cannot be edited.');
  end if;
  if p_expected_updated_at is not null and v_card.updated_at <> p_expected_updated_at then
    return tee_internal.api_error(
      v_request_id,
      'edit_conflict',
      'The course card changed on another device.',
      false,
      null,
      jsonb_build_object('updatedAt', v_card.updated_at)
    );
  end if;

  v_hole_count := jsonb_array_length(p_input->'holes');
  if v_hole_count not in (9, 18)
     or (select count(distinct (h->>'holeNumber')::integer)
         from jsonb_array_elements(p_input->'holes') h) <> v_hole_count
     or exists (
       select 1 from jsonb_array_elements(p_input->'holes') h
       where nullif(h->>'holeNumber', '') is null
          or nullif(h->>'par', '') is null
          or (h->>'holeNumber')::integer not between 1 and v_hole_count
          or (h->>'par')::integer not between 3 and 6
          or (nullif(h->>'yards', '') is not null and (h->>'yards')::integer not between 40 and 900)
     ) then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'Course cards require 9 or 18 contiguous holes with valid par and yardage.');
  end if;

  select count(*) into v_stroke_index_count
  from jsonb_array_elements(p_input->'holes') h
  where nullif(h->>'strokeIndex', '') is not null;
  if v_stroke_index_count not in (0, v_hole_count)
     or (v_stroke_index_count = v_hole_count and (
       (select count(distinct (h->>'strokeIndex')::integer)
        from jsonb_array_elements(p_input->'holes') h) <> v_hole_count
       or (select min((h->>'strokeIndex')::integer)
           from jsonb_array_elements(p_input->'holes') h) <> 1
       or (select max((h->>'strokeIndex')::integer)
           from jsonb_array_elements(p_input->'holes') h) <> v_hole_count
     )) then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'Stroke indexes must be omitted or be the complete unique range for the card.');
  end if;

  update public.course_cards set
    name = btrim(p_input->>'name'),
    course_name = btrim(p_input->>'courseName'),
    hole_count = v_hole_count
  where id = p_course_card_id;

  -- Round holes are independent immutable copies and are intentionally never
  -- touched when their source template changes.
  delete from public.course_card_holes where course_card_id = p_course_card_id;
  insert into public.course_card_holes (
    course_card_id, hole_number, par, stroke_index, yards
  )
  select
    p_course_card_id,
    (h->>'holeNumber')::smallint,
    (h->>'par')::smallint,
    nullif(h->>'strokeIndex', '')::smallint,
    nullif(h->>'yards', '')::smallint
  from jsonb_array_elements(p_input->'holes') h;

  return tee_internal.api_success(
    v_request_id,
    tee_internal.course_card_payload_v1(p_course_card_id)
  );
exception
  when invalid_text_representation or check_violation or not_null_violation or unique_violation then
    return tee_internal.api_error(v_request_id, 'invalid_course_card', 'One or more course-card fields are invalid.');
end;
$$;

create or replace function public.update_trip_round_v1(
  p_round_id uuid,
  p_input jsonb,
  p_expected_native_updated_at timestamptz default null
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
  v_round public.rounds%rowtype;
  v_card public.course_cards%rowtype;
  v_trip_id uuid;
  v_round_count integer;
  v_new_order smallint;
  v_shift record;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object'
     or not (p_input ?| array['courseCardId', 'teeTime', 'walkRide', 'tripOrder']) then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'At least one editable round field is required.');
  end if;

  select r.trip_id into v_trip_id from public.rounds r where r.id = p_round_id;
  if not found or v_trip_id is null then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Trip round not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_trip_id for update;
  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if tee_internal.trip_role(v_trip.id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can edit trip rounds.');
  end if;
  if v_trip.status is distinct from 'draft'
     or v_round.trip_round_status is distinct from 'scheduled' then
    return tee_internal.api_error(v_request_id, 'round_locked', 'Only scheduled rounds in draft trips can be edited.', false, v_trip.score_revision);
  end if;
  if exists (select 1 from public.trip_hole_scores s where s.round_id = p_round_id) then
    return tee_internal.api_error(v_request_id, 'round_has_scores', 'A round with scores cannot be edited.', false, v_trip.score_revision);
  end if;
  if p_expected_native_updated_at is not null
     and v_round.native_updated_at is distinct from p_expected_native_updated_at then
    return tee_internal.api_error(
      v_request_id,
      'edit_conflict',
      'The round changed on another device.',
      false,
      v_trip.score_revision,
      jsonb_build_object(
        'nativeUpdatedAt', v_round.native_updated_at,
        'tripOrder', v_round.trip_order,
        'teeTime', v_round.tee_time
      )
    );
  end if;

  if p_input ? 'courseCardId' then
    select * into v_card from public.course_cards cc
    where cc.id = (p_input->>'courseCardId')::uuid
      and cc.owner_id = v_user_id and cc.archived_at is null;
    if not found then
      return tee_internal.api_error(v_request_id, 'course_card_not_found', 'Course card not found.');
    end if;
    if (select count(*) from public.course_card_holes cch where cch.course_card_id = v_card.id) <> v_card.hole_count then
      return tee_internal.api_error(v_request_id, 'course_card_incomplete', 'The course card is missing holes.');
    end if;
  end if;

  select count(*) into v_round_count from public.rounds r where r.trip_id = v_trip.id;
  if p_input ? 'tripOrder' then
    v_new_order := (p_input->>'tripOrder')::smallint;
    if v_new_order not between 1 and v_round_count then
      return tee_internal.api_error(v_request_id, 'invalid_trip_order', 'Round order must be within the trip schedule.');
    end if;
    if v_new_order <> v_round.trip_order then
      update public.rounds set trip_order = null where id = p_round_id;
      if v_new_order < v_round.trip_order then
        for v_shift in
          select r.id from public.rounds r
          where r.trip_id = v_trip.id
            and r.trip_order >= v_new_order and r.trip_order < v_round.trip_order
          order by r.trip_order desc
        loop
          update public.rounds set trip_order = trip_order + 1 where id = v_shift.id;
        end loop;
      else
        for v_shift in
          select r.id from public.rounds r
          where r.trip_id = v_trip.id
            and r.trip_order > v_round.trip_order and r.trip_order <= v_new_order
          order by r.trip_order
        loop
          update public.rounds set trip_order = trip_order - 1 where id = v_shift.id;
        end loop;
      end if;
      update public.rounds set trip_order = v_new_order where id = p_round_id;
    end if;
  else
    v_new_order := v_round.trip_order;
  end if;

  update public.rounds r set
    course_name = case when p_input ? 'courseCardId' then v_card.course_name else r.course_name end,
    holes = case when p_input ? 'courseCardId' then v_card.hole_count else r.holes end,
    tee_time = case when p_input ? 'teeTime' then (p_input->>'teeTime')::timestamptz else r.tee_time end,
    walk_ride = case when p_input ? 'walkRide' then p_input->>'walkRide' else r.walk_ride end,
    native_updated_at = clock_timestamp()
  where r.id = p_round_id
  returning * into v_round;

  if p_input ? 'courseCardId' then
    delete from public.round_holes where round_id = p_round_id;
    insert into public.round_holes (round_id, hole_number, par, stroke_index, yards)
    select p_round_id, cch.hole_number, cch.par, cch.stroke_index, cch.yards
    from public.course_card_holes cch
    where cch.course_card_id = v_card.id
    order by cch.hole_number;
  end if;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'roundId', v_round.id,
    'publicId', v_round.public_id,
    'tripOrder', v_round.trip_order,
    'status', v_round.trip_round_status,
    'courseName', v_round.course_name,
    'teeTime', v_round.tee_time,
    'holeCount', v_round.holes,
    'walkRide', v_round.walk_ride,
    'nativeUpdatedAt', v_round.native_updated_at
  ));
exception
  when invalid_text_representation or datetime_field_overflow or check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'One or more round fields are invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'round_conflict', 'The round conflicts with another round.', true);
end;
$$;

create or replace function public.delete_trip_round_v1(
  p_round_id uuid,
  p_idempotency_key uuid,
  p_expected_native_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_request_hash bytea := tee_internal.request_hash(jsonb_build_object(
    'roundId', p_round_id,
    'expectedNativeUpdatedAt', p_expected_native_updated_at
  ));
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_round public.rounds%rowtype;
  v_trip_id uuid;
  v_has_legacy_scorecards boolean := false;
  v_remaining_count integer;
  v_shift record;
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
    if v_existing.operation = 'delete_trip_round_v1' and v_existing.request_hash = v_request_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  select r.trip_id into v_trip_id from public.rounds r where r.id = p_round_id;
  if not found or v_trip_id is null then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Trip round not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_trip_id for update;
  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if tee_internal.trip_role(v_trip.id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can delete trip rounds.');
  end if;
  if v_trip.status is distinct from 'draft'
     or v_round.trip_round_status is distinct from 'scheduled' then
    return tee_internal.api_error(v_request_id, 'round_locked', 'Only scheduled rounds in draft trips can be deleted.', false, v_trip.score_revision);
  end if;
  if p_expected_native_updated_at is not null
     and v_round.native_updated_at is distinct from p_expected_native_updated_at then
    return tee_internal.api_error(
      v_request_id,
      'edit_conflict',
      'The round changed on another device.',
      false,
      v_trip.score_revision,
      jsonb_build_object('nativeUpdatedAt', v_round.native_updated_at)
    );
  end if;
  if exists (select 1 from public.trip_hole_scores s where s.round_id = p_round_id)
     or exists (select 1 from public.trip_score_audit a where a.round_id = p_round_id) then
    return tee_internal.api_error(v_request_id, 'round_has_scores', 'A round with score history cannot be deleted.', false, v_trip.score_revision);
  end if;
  if to_regclass('public.scorecards') is not null then
    execute 'select exists (select 1 from public.scorecards where round_id = $1)'
      into v_has_legacy_scorecards using p_round_id;
  end if;
  if v_has_legacy_scorecards then
    return tee_internal.api_error(v_request_id, 'round_has_scores', 'A round with score history cannot be deleted.', false, v_trip.score_revision);
  end if;

  delete from public.round_responses where round_id = p_round_id;
  delete from public.rounds where id = p_round_id;
  for v_shift in
    select r.id from public.rounds r
    where r.trip_id = v_trip.id and r.trip_order > v_round.trip_order
    order by r.trip_order
  loop
    update public.rounds set trip_order = trip_order - 1 where id = v_shift.id;
  end loop;
  select count(*) into v_remaining_count from public.rounds r where r.trip_id = v_trip.id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'roundId', p_round_id,
    'deleted', true,
    'remainingRoundCount', v_remaining_count
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'delete_trip_round_v1', v_request_hash, v_response);
  return v_response;
exception
  when foreign_key_violation then
    return tee_internal.api_error(v_request_id, 'round_delete_blocked', 'Linked data prevents this round from being deleted.');
end;
$$;

create or replace function public.delete_trip_player_v1(
  p_trip_player_id uuid,
  p_idempotency_key uuid,
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
  v_request_hash bytea := tee_internal.request_hash(jsonb_build_object(
    'tripPlayerId', p_trip_player_id,
    'expectedUpdatedAt', p_expected_updated_at
  ));
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_player public.trip_players%rowtype;
  v_remaining_count integer;
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
    if v_existing.operation = 'delete_trip_player_v1' and v_existing.request_hash = v_request_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  select * into v_player from public.trip_players tp
  where tp.id = p_trip_player_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_player.trip_id for update;
  if tee_internal.trip_role(v_trip.id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can delete roster seats.');
  end if;
  if v_trip.status is distinct from 'draft' then
    return tee_internal.api_error(v_request_id, 'roster_locked', 'Roster seats can only be deleted while the trip is a draft.', false, v_trip.score_revision);
  end if;
  if v_player.role = 'captain' then
    return tee_internal.api_error(v_request_id, 'captain_role_required', 'Transfer ownership before deleting the captain seat.');
  end if;
  if p_expected_updated_at is not null and v_player.updated_at <> p_expected_updated_at then
    return tee_internal.api_error(
      v_request_id,
      'edit_conflict',
      'The roster seat changed on another device.',
      false,
      v_trip.score_revision,
      jsonb_build_object('updatedAt', v_player.updated_at)
    );
  end if;
  if exists (select 1 from public.trip_hole_scores s where s.trip_player_id = p_trip_player_id)
     or exists (select 1 from public.trip_score_audit a where a.trip_player_id = p_trip_player_id) then
    return tee_internal.api_error(v_request_id, 'player_has_scores', 'A roster seat with score history cannot be deleted.', false, v_trip.score_revision);
  end if;
  delete from public.extension_sessions where trip_player_id = p_trip_player_id;
  delete from public.trip_players where id = p_trip_player_id;
  select count(*) into v_remaining_count from public.trip_players tp where tp.trip_id = v_trip.id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'tripPlayerId', p_trip_player_id,
    'deleted', true,
    'remainingPlayerCount', v_remaining_count,
    'scoreRevision', v_trip.score_revision
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'delete_trip_player_v1', v_request_hash, v_response);
  return v_response;
exception
  when foreign_key_violation then
    return tee_internal.api_error(v_request_id, 'player_delete_blocked', 'Linked data prevents this roster seat from being deleted.');
end;
$$;

create or replace function public.get_account_deletion_blockers_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_blockers jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'tripId', t.id,
    'publicId', t.public_id,
    'name', t.name,
    'status', t.status,
    'requiredAction', 'transfer_ownership'
  ) order by t.starts_on, t.id), '[]'::jsonb) into v_blockers
  from public.trips t
  where t.owner_id = v_user_id and t.status in ('draft', 'ready', 'live');
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'canDelete', jsonb_array_length(v_blockers) = 0,
    'ownedTrips', v_blockers
  ));
end;
$$;

-- Fail the legacy Expo deletion path closed whenever native trip data exists.
-- The verified linked Auth/Storage/FK inventory is still required before a
-- complete native account-deletion workflow can be shipped.
create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = 'P0001', message = 'unauthenticated';
  end if;
  if exists (
    select 1 from public.trips t
    where t.owner_id = v_user_id
       or exists (
         select 1 from public.trip_players tp
         where tp.trip_id = t.id and tp.claimed_user_id = v_user_id
       )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'native_account_deletion_required',
      detail = 'Use TeeCircle 2.0 account deletion after the linked Auth/Storage baseline is reviewed.';
  end if;

  delete from public.friendships where user_low = v_user_id or user_high = v_user_id;
  delete from public.group_members where user_id = v_user_id;
  delete from public.round_responses where user_id = v_user_id;
  if to_regclass('public.push_tokens') is not null then
    delete from public.push_tokens where user_id = v_user_id;
  end if;
  delete from public.rounds where created_by = v_user_id and trip_id is null;
  delete from public.groups where created_by = v_user_id;
  delete from public.profiles where id = v_user_id;
end;
$$;

-- Include optimistic versions in the main bootstrap so clients can safely
-- invoke the edit/delete commands after any cold launch.
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
        'isCurrentUser', tp.claimed_user_id = v_user_id,
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

-- Realtime transports only a refresh hint; clients still fetch the canonical
-- authoritative snapshot DTO after receiving an INSERT/UPDATE event.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime'
      and pr.prrelid = 'public.trip_leaderboard_snapshots'::regclass
  ) then
    alter publication supabase_realtime add table public.trip_leaderboard_snapshots;
  end if;
end
$$;

revoke all on function public.update_course_card_v1(uuid, jsonb, timestamptz) from public;
revoke all on function public.update_trip_round_v1(uuid, jsonb, timestamptz) from public;
revoke all on function public.delete_trip_round_v1(uuid, uuid, timestamptz) from public;
revoke all on function public.delete_trip_player_v1(uuid, uuid, timestamptz) from public;
revoke all on function public.delete_user_account() from public;

grant execute on function public.update_course_card_v1(uuid, jsonb, timestamptz) to authenticated;
grant execute on function public.update_trip_round_v1(uuid, jsonb, timestamptz) to authenticated;
grant execute on function public.delete_trip_round_v1(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.delete_trip_player_v1(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.delete_user_account() to authenticated;
