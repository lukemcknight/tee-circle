set lock_timeout = '10s';
set statement_timeout = '5min';

-- Isolate native trip rounds from the linked project's legacy round machinery.
-- Native ownership lives on trips/trip_players; legacy rounds.created_by and
-- round_responses remain exclusively for the Expo rollback surface.


-- Native round creation ----------------------------------------------------

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
    null,
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
      coalesce(rr.response::text, 'pending') as response,
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
    left join public.player_handicap_profiles hp
      on hp.user_id = rr.user_id and hp.is_hidden = false
    where rr.round_id = p_legacy_round_id and rr.user_id <> v_user_id
  )
  insert into public.trip_players (
    trip_id, claimed_user_id, display_name, role, rsvp, handicap_snapshot
  )
  select v_trip.id, null,
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
    v_legacy.walk_ride, null,
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

revoke all on function public.create_trip_round_v1(uuid, jsonb, uuid)
  from public, anon;
revoke all on function public.convert_legacy_round_v1(uuid, text, uuid)
  from public, anon;
grant execute on function public.create_trip_round_v1(uuid, jsonb, uuid)
  to authenticated;
grant execute on function public.convert_legacy_round_v1(uuid, text, uuid)
  to authenticated;

-- Legacy trigger/RPC isolation ---------------------------------------------

create or replace function public.create_creator_response()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.trip_id is not null or new.created_by is null then
    return new;
  end if;

  insert into public.round_responses (round_id, user_id, response, responded_at)
  values (new.id, new.created_by, 'yes', now())
  on conflict (round_id, user_id) do nothing;
  return new;
end;
$$;

create or replace function public.lock_round_if_ready()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_trip_id uuid;
begin
  select r.trip_id into v_trip_id
  from public.rounds r
  where r.id = new.round_id;

  if not found or v_trip_id is not null then
    return new;
  end if;

  if (
    select count(*)
    from public.round_responses rr
    where rr.round_id = new.round_id and rr.response = 'yes'
  ) >= 2 then
    update public.rounds
    set status = 'locked'
    where id = new.round_id and trip_id is null;
  end if;
  return new;
end;
$$;

create or replace function public.invite_friend_to_round(
  p_round_id uuid,
  p_friend_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.rounds%rowtype;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_round
  from public.rounds r
  where r.id = p_round_id;
  if not found then
    raise exception 'Round not found';
  end if;
  if v_round.trip_id is not null
     or v_round.created_by is distinct from v_user_id then
    raise exception 'Only the creator can invite';
  end if;

  if not exists (
    select 1
    from public.friendships f
    where f.user_low = least(v_user_id, p_friend_id)
      and f.user_high = greatest(v_user_id, p_friend_id)
      and f.status = 'accepted'
  ) then
    raise exception 'Not friends';
  end if;

  insert into public.round_responses (round_id, user_id, response)
  values (p_round_id, p_friend_id, 'pending')
  on conflict (round_id, user_id) do nothing;
  return true;
end;
$$;

revoke all on function public.create_creator_response()
  from public, anon, authenticated;
revoke all on function public.lock_round_if_ready()
  from public, anon, authenticated;
revoke all on function public.invite_friend_to_round(uuid, uuid)
  from public, anon;
grant execute on function public.invite_friend_to_round(uuid, uuid)
  to authenticated;

-- The Expo view keeps its exact established column order, but native trip
-- rounds must never enter the legacy discovery surface.
create or replace function tee_internal.current_user_has_legacy_round_response_v1(
  p_round_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.round_responses rr
      where rr.round_id = p_round_id
        and rr.user_id = auth.uid()
    );
$$;

revoke all on function tee_internal.current_user_has_legacy_round_response_v1(uuid)
  from public, anon;
grant execute on function tee_internal.current_user_has_legacy_round_response_v1(uuid)
  to authenticated;

alter table public.rounds enable row level security;
drop policy if exists "Legacy round participants can read rounds"
  on public.rounds;
create policy "Legacy round participants can read rounds"
on public.rounds as permissive
for select to authenticated
using (
  trip_id is null
  and (
    created_by = auth.uid()
    or tee_internal.current_user_has_legacy_round_response_v1(id)
  )
);

create or replace view public.visible_rounds
with (security_invoker = true, security_barrier = true)
as
select distinct
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
from public.rounds r
left join public.round_responses rr on rr.round_id = r.id
where r.trip_id is null
  and (r.created_by = auth.uid() or rr.user_id = auth.uid());

revoke all on table public.visible_rounds from public, anon;
grant select on table public.rounds, public.round_responses to authenticated;
grant select on table public.visible_rounds to authenticated;

-- Restrictive RLS boundary -------------------------------------------------

create or replace function tee_internal.round_is_legacy_v1(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id and r.trip_id is null
  );
$$;

create or replace function tee_internal.scorecard_is_legacy_v1(p_scorecard_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.scorecards s
    join public.rounds r on r.id = s.round_id
    where s.id = p_scorecard_id and r.trip_id is null
  );
$$;

revoke all on function tee_internal.round_is_legacy_v1(uuid)
  from public, anon;
revoke all on function tee_internal.scorecard_is_legacy_v1(uuid)
  from public, anon;
grant execute on function tee_internal.round_is_legacy_v1(uuid)
  to authenticated;
grant execute on function tee_internal.scorecard_is_legacy_v1(uuid)
  to authenticated;

alter table public.rounds enable row level security;
alter table public.round_responses enable row level security;
alter table public.scorecards enable row level security;
alter table public.scorecard_holes enable row level security;
alter table public.handicap_differentials enable row level security;

drop policy if exists "Legacy boundary permits legacy or member round reads"
  on public.rounds;
create policy "Legacy boundary permits legacy or member round reads"
on public.rounds as restrictive
for select to authenticated
using (
  trip_id is null
  or tee_internal.current_user_is_trip_member(trip_id)
);

drop policy if exists "Legacy boundary blocks native round responses"
  on public.round_responses;
create policy "Legacy boundary blocks native round responses"
on public.round_responses as restrictive
for all to authenticated
using (tee_internal.round_is_legacy_v1(round_id))
with check (tee_internal.round_is_legacy_v1(round_id));

drop policy if exists "Legacy boundary blocks native scorecards"
  on public.scorecards;
create policy "Legacy boundary blocks native scorecards"
on public.scorecards as restrictive
for all to authenticated
using (tee_internal.round_is_legacy_v1(round_id))
with check (tee_internal.round_is_legacy_v1(round_id));

drop policy if exists "Legacy boundary blocks native scorecard holes"
  on public.scorecard_holes;
create policy "Legacy boundary blocks native scorecard holes"
on public.scorecard_holes as restrictive
for all to authenticated
using (tee_internal.scorecard_is_legacy_v1(scorecard_id))
with check (tee_internal.scorecard_is_legacy_v1(scorecard_id));

drop policy if exists "Legacy boundary blocks native handicap differentials"
  on public.handicap_differentials;
create policy "Legacy boundary blocks native handicap differentials"
on public.handicap_differentials as restrictive
for all to authenticated
using (tee_internal.scorecard_is_legacy_v1(scorecard_id))
with check (tee_internal.scorecard_is_legacy_v1(scorecard_id));

-- Native account deletion remains deliberately fail-closed. This migration
-- neither adds delete_account_v1 nor loosens any attribution foreign key.
