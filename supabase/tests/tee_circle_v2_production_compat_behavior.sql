-- Production-shaped compatibility checks for the legacy rounds hierarchy.
-- Run only after verified_legacy_schema.sql and every ordered v2 migration.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';
update tee_internal.runtime_flags set enabled = false
where key = 'purchases_required';

insert into auth.users (id) values
  ('a1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002'),
  ('a1000000-0000-4000-8000-000000000003'),
  ('a1000000-0000-4000-8000-000000000004'),
  ('a1000000-0000-4000-8000-000000000005');

insert into public.profiles (id, full_name, username) values
  ('a1000000-0000-4000-8000-000000000001', 'Compat Captain', 'compat-captain'),
  ('a1000000-0000-4000-8000-000000000002', 'Compat Yes', 'compat-yes'),
  ('a1000000-0000-4000-8000-000000000003', 'Compat No', 'compat-no'),
  ('a1000000-0000-4000-8000-000000000004', 'Compat Pending', 'compat-pending'),
  ('a1000000-0000-4000-8000-000000000005', 'Compat Outsider', 'compat-outsider');

insert into public.player_handicap_profiles (
  user_id, handicap_index, is_hidden
) values
  ('a1000000-0000-4000-8000-000000000002', 12.4, false),
  ('a1000000-0000-4000-8000-000000000003', 21.7, true);

insert into public.friendships (
  id, user_low, user_high, requested_by, status, accepted_at
) values
  (
    'a1100000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000001',
    'accepted', now()
  ),
  (
    'a1100000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000003',
    'a1000000-0000-4000-8000-000000000001',
    'accepted', now()
  ),
  (
    'a1100000-0000-4000-8000-000000000003',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000004',
    'a1000000-0000-4000-8000-000000000001',
    'accepted', now()
  );

insert into public.course_cards (
  id, owner_id, name, course_name, hole_count
) values (
  'a1200000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'Compat card', 'Production Shape Club', 9
);

insert into public.course_card_holes (
  course_card_id, hole_number, par, stroke_index, yards
)
select
  'a1200000-0000-4000-8000-000000000001',
  hole_number,
  4,
  hole_number,
  300 + hole_number
from generate_series(1, 9) hole_number;

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);

-- Exercise the actual native commands. Native rows must not bind to the
-- profile-backed legacy creator FK or fire the legacy response trigger.
do $$
declare
  v_trip_result jsonb;
  v_round_result jsonb;
  v_trip_id uuid;
  v_round_id uuid;
  v_created_by uuid;
  v_legacy_status text;
begin
  v_trip_result := public.create_trip_v1(
    jsonb_build_object(
      'name', 'Production Compatibility Trip',
      'startsOn', '2026-08-01',
      'endsOn', '2026-08-01',
      'timezone', 'America/New_York',
      'enabledFormats', jsonb_build_array('stableford'),
      'primaryFormat', 'stableford',
      'scoringMode', 'gross',
      'captainDisplayName', 'Compat Captain'
    ),
    'a1300000-0000-4000-8000-000000000001'
  );
  if v_trip_result ? 'error' then
    raise exception 'production-shaped trip creation failed: %', v_trip_result;
  end if;
  v_trip_id := (v_trip_result#>>'{data,tripId}')::uuid;

  v_round_result := public.create_trip_round_v1(
    v_trip_id,
    jsonb_build_object(
      'courseCardId', 'a1200000-0000-4000-8000-000000000001',
      'teeTime', '2026-08-01T09:00:00-04:00',
      'walkRide', 'ride'
    ),
    'a1300000-0000-4000-8000-000000000002'
  );
  if v_round_result ? 'error' then
    raise exception 'production-shaped native round creation failed: %', v_round_result;
  end if;
  v_round_id := (v_round_result#>>'{data,roundId}')::uuid;

  select r.created_by, r.status::text
  into v_created_by, v_legacy_status
  from public.rounds r where r.id = v_round_id;
  if v_created_by is not null or v_legacy_status <> 'open' then
    raise exception 'native round crossed the legacy creator/status contract: %, %',
      v_created_by, v_legacy_status;
  end if;
  if exists (
    select 1 from public.round_responses rr where rr.round_id = v_round_id
  ) then
    raise exception 'native round fired the legacy creator-response trigger';
  end if;
  if exists (
    select 1 from public.visible_rounds vr where vr.id = v_round_id
  ) then
    raise exception 'native round leaked through legacy visible_rounds';
  end if;

  perform set_config('teecircle_test.native_trip_id', v_trip_id::text, true);
  perform set_config('teecircle_test.native_round_id', v_round_id::text, true);
end
$$;

-- The legacy invitation RPC must reject native rounds without creating a
-- response, even when the caller owns the native trip and the friend is valid.
do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.invite_friend_to_round(
      current_setting('teecircle_test.native_round_id')::uuid,
      'a1000000-0000-4000-8000-000000000002'
    );
  exception when others then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'legacy invitation RPC accepted a native round';
  end if;
  if exists (
    select 1 from public.round_responses rr
    where rr.round_id = current_setting('teecircle_test.native_round_id')::uuid
  ) then
    raise exception 'rejected native invitation persisted a legacy response';
  end if;
end
$$;

-- Legacy table APIs remain available for legacy data but cannot attach their
-- response/scorecard hierarchy to a native round.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  v_response_blocked boolean := false;
  v_scorecard_blocked boolean := false;
begin
  begin
    insert into public.round_responses (round_id, user_id, response)
    values (
      current_setting('teecircle_test.native_round_id')::uuid,
      'a1000000-0000-4000-8000-000000000001',
      'yes'
    );
  exception when insufficient_privilege then
    v_response_blocked := true;
  end;

  begin
    insert into public.scorecards (
      round_id, player_id, entered_by, holes
    ) values (
      current_setting('teecircle_test.native_round_id')::uuid,
      'a1000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      9
    );
  exception when insufficient_privilege then
    v_scorecard_blocked := true;
  end;

  if not v_response_blocked then
    raise exception 'legacy response table accepted a native parent';
  end if;
  if not v_scorecard_blocked then
    raise exception 'legacy scorecard table accepted a native parent';
  end if;
end
$$;

reset role;

-- A legacy insert still creates the creator's enum-backed yes response.
insert into public.rounds (
  id, group_id, course_name, tee_time, holes, walk_ride, created_by
) values (
  'a1400000-0000-4000-8000-000000000001',
  null,
  'Legacy Compatibility Club',
  '2026-07-30T08:00:00-04:00',
  9,
  'walk',
  'a1000000-0000-4000-8000-000000000001'
);

do $$
begin
  if not exists (
    select 1 from public.round_responses rr
    where rr.round_id = 'a1400000-0000-4000-8000-000000000001'
      and rr.user_id = 'a1000000-0000-4000-8000-000000000001'
      and rr.response::text = 'yes'
  ) then
    raise exception 'legacy creator-response trigger no longer works';
  end if;
  if not exists (
    select 1 from public.visible_rounds vr
    where vr.id = 'a1400000-0000-4000-8000-000000000001'
  ) then
    raise exception 'legacy round disappeared from visible_rounds';
  end if;
end
$$;

-- The preserved invitation RPC creates enum-backed pending responses for
-- accepted friends on legacy rounds.
select public.invite_friend_to_round(
  'a1400000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002'
);
select public.invite_friend_to_round(
  'a1400000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000003'
);
select public.invite_friend_to_round(
  'a1400000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000004'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000002',
  true
);
update public.round_responses
set response = 'yes', responded_at = now()
where round_id = 'a1400000-0000-4000-8000-000000000001'
  and user_id = 'a1000000-0000-4000-8000-000000000002';

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000003',
  true
);
update public.round_responses
set response = 'no', responded_at = now()
where round_id = 'a1400000-0000-4000-8000-000000000001'
  and user_id = 'a1000000-0000-4000-8000-000000000003';
reset role;

do $$
begin
  if (select rr.response::text from public.round_responses rr
      where rr.round_id = 'a1400000-0000-4000-8000-000000000001'
        and rr.user_id = 'a1000000-0000-4000-8000-000000000002') <> 'yes'
     or (select rr.response::text from public.round_responses rr
         where rr.round_id = 'a1400000-0000-4000-8000-000000000001'
           and rr.user_id = 'a1000000-0000-4000-8000-000000000003') <> 'no' then
    raise exception 'legacy enum response updates no longer work';
  end if;
end
$$;

-- The security-invoker view must work through RLS for every response value,
-- while outsiders remain unable to discover the round.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);
do $$
begin
  if not exists (
    select 1 from public.visible_rounds vr
    where vr.id = 'a1400000-0000-4000-8000-000000000001'
  ) then
    raise exception 'legacy creator cannot read visible_rounds through RLS';
  end if;
end
$$;

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000002',
  true
);
do $$
begin
  if not exists (
    select 1 from public.visible_rounds vr
    where vr.id = 'a1400000-0000-4000-8000-000000000001'
  ) then
    raise exception 'yes invitee cannot read visible_rounds through RLS';
  end if;
end
$$;

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000003',
  true
);
do $$
begin
  if not exists (
    select 1 from public.visible_rounds vr
    where vr.id = 'a1400000-0000-4000-8000-000000000001'
  ) then
    raise exception 'no invitee cannot read visible_rounds through RLS';
  end if;
end
$$;

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000004',
  true
);
do $$
begin
  if not exists (
    select 1 from public.visible_rounds vr
    where vr.id = 'a1400000-0000-4000-8000-000000000001'
  ) then
    raise exception 'pending invitee cannot read visible_rounds through RLS';
  end if;
end
$$;

select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000005',
  true
);
do $$
begin
  if exists (
    select 1 from public.visible_rounds vr
    where vr.id = 'a1400000-0000-4000-8000-000000000001'
  ) then
    raise exception 'legacy outsider discovered visible_rounds through RLS';
  end if;
end
$$;
reset role;

-- Conversion must read the production response enum, emit text RSVP values,
-- and create an isolated native copy without legacy creator/response state.
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  v_result jsonb;
  v_trip_id uuid;
  v_round_id uuid;
begin
  v_result := public.convert_legacy_round_v1(
    'a1400000-0000-4000-8000-000000000001',
    'Converted Enum Trip',
    'a1300000-0000-4000-8000-000000000003'
  );
  if v_result ? 'error' then
    raise exception 'enum-backed legacy conversion failed: %', v_result;
  end if;
  v_trip_id := (v_result#>>'{data,tripId}')::uuid;
  v_round_id := (v_result#>>'{data,roundId}')::uuid;

  if not exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_trip_id
      and tp.display_name = 'Compat Yes'
      and tp.rsvp = 'yes'
      and tp.handicap_snapshot = 12.4
  ) or not exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_trip_id
      and tp.display_name = 'Compat No'
      and tp.rsvp = 'no'
  ) or not exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_trip_id
      and tp.display_name = 'Compat Pending'
      and tp.rsvp = 'pending'
  ) then
    raise exception 'response enum did not convert to text RSVP values';
  end if;

  if exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_trip_id
      and tp.role <> 'captain'
      and tp.claimed_user_id is not null
  ) then
    raise exception 'legacy invitees were auto-claimed into the converted trip';
  end if;
  if not exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_trip_id
      and tp.role = 'captain'
      and tp.claimed_user_id = 'a1000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'converted captain did not retain their own roster claim';
  end if;
  if exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_trip_id
      and tp.display_name = 'Compat No'
      and tp.handicap_snapshot is not null
  ) then
    raise exception 'hidden legacy handicap leaked into the converted trip';
  end if;

  if (select r.created_by from public.rounds r where r.id = v_round_id) is not null
     or exists (
       select 1 from public.round_responses rr where rr.round_id = v_round_id
     ) then
    raise exception 'converted native round retained legacy creator/response state';
  end if;
end
$$;

rollback;
