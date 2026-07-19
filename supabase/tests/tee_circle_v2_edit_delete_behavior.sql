-- Edit/delete and legacy-deletion safety regression. Run only against the
-- disposable fixture through run-local-v2.sh.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

insert into auth.users (id) values
  ('71000000-0000-4000-8000-000000000001'),
  ('71000000-0000-4000-8000-000000000002'),
  ('71000000-0000-4000-8000-000000000003'),
  ('71000000-0000-4000-8000-000000000004');

insert into public.profiles (id, full_name) values
  ('71000000-0000-4000-8000-000000000001', 'Edit Captain'),
  ('71000000-0000-4000-8000-000000000002', 'Edit Player'),
  ('71000000-0000-4000-8000-000000000003', 'Other Owner'),
  ('71000000-0000-4000-8000-000000000004', 'Legacy Only');

insert into public.course_cards (
  id, owner_id, name, course_name, hole_count, updated_at
) values
  ('71500000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001', 'Old tees', 'Old Course', 9, '2026-07-13T10:00:00Z'),
  ('71500000-0000-4000-8000-000000000002', '71000000-0000-4000-8000-000000000001', 'New tees', 'New Course', 9, '2026-07-13T10:00:00Z'),
  ('71500000-0000-4000-8000-000000000003', '71000000-0000-4000-8000-000000000003', 'Private tees', 'Private Course', 9, '2026-07-13T10:00:00Z');

insert into public.course_card_holes (course_card_id, hole_number, par, stroke_index, yards)
select card_id, hole,
  case card_id
    when '71500000-0000-4000-8000-000000000002'::uuid then 5
    when '71500000-0000-4000-8000-000000000003'::uuid then 3
    else 4
  end,
  hole,
  300 + hole
from (
  values
    ('71500000-0000-4000-8000-000000000001'::uuid),
    ('71500000-0000-4000-8000-000000000002'::uuid),
    ('71500000-0000-4000-8000-000000000003'::uuid)
) cards(card_id)
cross join generate_series(1, 9) hole;

insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status,
  enabled_formats, primary_format, scoring_mode, score_revision
) values (
  '72000000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000002',
  '71000000-0000-4000-8000-000000000001',
  'Editable Trip', '2026-08-01', '2026-08-02', 'draft',
  array['stableford'], 'stableford', 'gross', 0
);

insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp, handicap_snapshot,
  updated_at
) values
  ('73000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes', 5, '2026-07-13T10:00:00Z'),
  ('73000000-0000-4000-8000-000000000002', '72000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000002', 'Player', 'player', 'yes', 10, '2026-07-13T10:00:00Z'),
  ('73000000-0000-4000-8000-000000000003', '72000000-0000-4000-8000-000000000001', null, 'Open Seat', 'player', 'yes', 12, '2026-07-13T10:00:00Z'),
  ('73000000-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000001', null, 'Scored Seat', 'player', 'yes', 14, '2026-07-13T10:00:00Z'),
  ('73000000-0000-4000-8000-000000000005', '72000000-0000-4000-8000-000000000001', null, 'Ready Locked', 'player', 'yes', 16, '2026-07-13T10:00:00Z');

-- Original legacy round must survive deletion of a converted native copy.
insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, status, created_by
) values (
  '74000000-0000-4000-8000-000000000001', 'Legacy Source',
  '2026-07-01T12:00:00Z', 9, 'ride', 'open',
  '71000000-0000-4000-8000-000000000001'
);

insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, status, created_by,
  trip_id, trip_order, public_id, trip_round_status,
  legacy_source_round_id, native_updated_at
) values
  ('74000000-0000-4000-8000-000000000002', 'Old Course', '2026-08-01T12:00:00Z', 9, 'ride', 'open', '71000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001', 1, '74000000-0000-4000-8000-000000000012', 'scheduled', null, '2026-07-13T10:00:00Z'),
  ('74000000-0000-4000-8000-000000000003', 'Old Course', '2026-08-02T12:00:00Z', 9, 'ride', 'open', '71000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000001', 2, '74000000-0000-4000-8000-000000000013', 'scheduled', '74000000-0000-4000-8000-000000000001', '2026-07-13T10:00:00Z');

insert into public.round_holes (round_id, hole_number, par, stroke_index, yards)
select round_id, hole, 4, hole, 300 + hole
from (
  values
    ('74000000-0000-4000-8000-000000000002'::uuid),
    ('74000000-0000-4000-8000-000000000003'::uuid)
) rounds(round_id)
cross join generate_series(1, 9) hole;

insert into public.trip_round_players (
  round_id, trip_player_id, course_handicap, playing_handicap, status
)
select r.id, p.id, 10, 10, 'active'
from public.rounds r
cross join public.trip_players p
where r.trip_id = '72000000-0000-4000-8000-000000000001'
  and p.trip_id = r.trip_id;

select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);

-- Updating a reusable template never mutates an already-copied round card.
do $$
declare result jsonb;
begin
  result := public.update_course_card_v1(
    '71500000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'name', 'Updated tees',
      'courseName', 'Updated Course',
      'holes', (
        select jsonb_agg(jsonb_build_object(
          'holeNumber', hole, 'par', 5, 'strokeIndex', hole, 'yards', 350 + hole
        ) order by hole) from generate_series(1, 9) hole
      )
    ),
    '2026-07-13T10:00:00Z'
  );
  if result#>>'{data,courseName}' <> 'Updated Course'
     or result#>>'{data,holes,0,par}' <> '5' then
    raise exception 'course-card update failed: %', result;
  end if;
  if (select par from public.round_holes where round_id = '74000000-0000-4000-8000-000000000002' and hole_number = 1) <> 4 then
    raise exception 'template update mutated historical round holes';
  end if;
end
$$;

do $$
declare result jsonb;
begin
  result := public.update_course_card_v1(
    '71500000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'name', 'Stale', 'courseName', 'Stale',
      'holes', (select jsonb_agg(jsonb_build_object('holeNumber', hole, 'par', 4, 'strokeIndex', hole)) from generate_series(1, 9) hole)
    ),
    '2026-07-13T10:00:00Z'
  );
  if result#>>'{error,code}' <> 'edit_conflict' then raise exception 'stale card update was accepted: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000003', true);
do $$
declare result jsonb;
begin
  result := public.update_course_card_v1(
    '71500000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'name', 'Foreign', 'courseName', 'Foreign',
      'holes', (select jsonb_agg(jsonb_build_object('holeNumber', hole, 'par', 4, 'strokeIndex', hole)) from generate_series(1, 9) hole)
    )
  );
  if result#>>'{error,code}' <> 'forbidden' then raise exception 'foreign card edit was accepted: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);

-- Replacing/reordering a draft round preserves its IDs and participation.
do $$
declare result jsonb;
begin
  result := public.update_trip_round_v1(
    '74000000-0000-4000-8000-000000000003',
    jsonb_build_object(
      'courseCardId', '71500000-0000-4000-8000-000000000002',
      'teeTime', '2026-08-01T15:30:00Z',
      'walkRide', 'walk',
      'tripOrder', 1
    ),
    '2026-07-13T10:00:00Z'
  );
  if result#>>'{data,tripOrder}' <> '1'
     or result#>>'{data,courseName}' <> 'New Course'
     or result#>>'{data,walkRide}' <> 'walk' then
    raise exception 'round update failed: %', result;
  end if;
  if (select trip_order from public.rounds where id = '74000000-0000-4000-8000-000000000002') <> 2
     or (select par from public.round_holes where round_id = '74000000-0000-4000-8000-000000000003' and hole_number = 1) <> 5
     or (select count(*) from public.trip_round_players where round_id = '74000000-0000-4000-8000-000000000003') <> 5 then
    raise exception 'round reorder/card copy/participation invariant failed';
  end if;
end
$$;

do $$
declare result jsonb;
begin
  result := public.update_trip_round_v1(
    '74000000-0000-4000-8000-000000000003',
    '{"teeTime":"2026-08-01T16:00:00Z"}'::jsonb,
    '2026-07-13T10:00:00Z'
  );
  if result#>>'{error,code}' <> 'edit_conflict' then raise exception 'stale round update was accepted: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000002', true);
do $$
declare result jsonb;
begin
  result := public.update_trip_round_v1('74000000-0000-4000-8000-000000000002', '{"walkRide":"walk"}'::jsonb);
  if result#>>'{error,code}' <> 'forbidden' then raise exception 'noncaptain round edit was accepted: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);

-- A score is a hard deletion barrier for both its round and stable seat.
insert into public.trip_hole_scores (
  id, trip_id, round_id, trip_player_id, hole_number, strokes, penalties,
  recorded_by_user_id, revision, idempotency_key
) values (
  '74500000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000001',
  '74000000-0000-4000-8000-000000000002',
  '73000000-0000-4000-8000-000000000004',
  1, 5, 0, '71000000-0000-4000-8000-000000000001', 1,
  '74500000-0000-4000-8000-000000000002'
);
insert into public.trip_score_audit (
  score_id, trip_id, round_id, trip_player_id, hole_number, strokes,
  penalties, actor_user_id, revision, idempotency_key
) values (
  '74500000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000001',
  '74000000-0000-4000-8000-000000000002',
  '73000000-0000-4000-8000-000000000004',
  1, 5, 0, '71000000-0000-4000-8000-000000000001', 1,
  '74500000-0000-4000-8000-000000000003'
);

do $$
declare round_result jsonb; player_result jsonb; captain_result jsonb;
begin
  round_result := public.delete_trip_round_v1(
    '74000000-0000-4000-8000-000000000002',
    '75000000-0000-4000-8000-000000000001'
  );
  player_result := public.delete_trip_player_v1(
    '73000000-0000-4000-8000-000000000004',
    '75000000-0000-4000-8000-000000000002'
  );
  captain_result := public.delete_trip_player_v1(
    '73000000-0000-4000-8000-000000000001',
    '75000000-0000-4000-8000-000000000003'
  );
  if round_result#>>'{error,code}' <> 'round_has_scores'
     or player_result#>>'{error,code}' <> 'player_has_scores'
     or captain_result#>>'{error,code}' <> 'captain_role_required' then
    raise exception 'score/captain deletion barriers failed: %, %, %', round_result, player_result, captain_result;
  end if;
end
$$;

-- The unscored converted round deletes idempotently, compacts order, and
-- leaves its original legacy source untouched.
do $$
declare first_result jsonb; replay_result jsonb; reused_result jsonb;
begin
  first_result := public.delete_trip_round_v1(
    '74000000-0000-4000-8000-000000000003',
    '75000000-0000-4000-8000-000000000004'
  );
  replay_result := public.delete_trip_round_v1(
    '74000000-0000-4000-8000-000000000003',
    '75000000-0000-4000-8000-000000000004'
  );
  reused_result := public.delete_trip_round_v1(
    '74000000-0000-4000-8000-000000000002',
    '75000000-0000-4000-8000-000000000004'
  );
  if first_result#>>'{data,deleted}' <> 'true'
     or replay_result#>>'{data,deleted}' <> 'true'
     or reused_result#>>'{error,code}' <> 'idempotency_key_reused'
     or not exists (select 1 from public.rounds where id = '74000000-0000-4000-8000-000000000001')
     or (select trip_order from public.rounds where id = '74000000-0000-4000-8000-000000000002') <> 1 then
    raise exception 'draft round deletion invariant failed: %, %, %', first_result, replay_result, reused_result;
  end if;
end
$$;

do $$
declare first_result jsonb; replay_result jsonb;
begin
  first_result := public.delete_trip_player_v1(
    '73000000-0000-4000-8000-000000000003',
    '75000000-0000-4000-8000-000000000005',
    '2026-07-13T10:00:00Z'
  );
  replay_result := public.delete_trip_player_v1(
    '73000000-0000-4000-8000-000000000003',
    '75000000-0000-4000-8000-000000000005',
    '2026-07-13T10:00:00Z'
  );
  if first_result#>>'{data,deleted}' <> 'true'
     or replay_result#>>'{data,deleted}' <> 'true'
     or exists (select 1 from public.trip_round_players where trip_player_id = '73000000-0000-4000-8000-000000000003') then
    raise exception 'draft roster deletion invariant failed: %, %', first_result, replay_result;
  end if;
end
$$;

update public.trips set status = 'ready' where id = '72000000-0000-4000-8000-000000000001';
do $$
declare result jsonb; bootstrap jsonb;
begin
  result := public.delete_trip_player_v1(
    '73000000-0000-4000-8000-000000000005',
    '75000000-0000-4000-8000-000000000006'
  );
  bootstrap := public.get_trip_bootstrap_v1('72000000-0000-4000-8000-000000000001');
  if result#>>'{error,code}' <> 'roster_locked'
     or bootstrap#>>'{data,roster,0,updatedAt}' is null
     or bootstrap#>>'{data,rounds,0,nativeUpdatedAt}' is null then
    raise exception 'ready lock/bootstrap optimistic versions failed: %, %', result, bootstrap;
  end if;
end
$$;

-- Completed ownership is not an active blocker; draft/ready/live ownership is.
do $$
declare blockers jsonb;
begin
  blockers := public.get_account_deletion_blockers_v1();
  if blockers#>>'{data,canDelete}' <> 'false'
     or blockers#>>'{data,ownedTrips,0,status}' <> 'ready' then
    raise exception 'active ownership blocker failed: %', blockers;
  end if;
end
$$;

insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status
) values (
  '76000000-0000-4000-8000-000000000001',
  '76000000-0000-4000-8000-000000000002',
  '71000000-0000-4000-8000-000000000003',
  'Completed Trip', '2026-06-01', '2026-06-01', 'completed'
);
select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000003', true);
do $$
declare blockers jsonb;
begin
  blockers := public.get_account_deletion_blockers_v1();
  if blockers#>>'{data,canDelete}' <> 'true' then
    raise exception 'completed trip was treated as active deletion blocker: %', blockers;
  end if;
end
$$;

-- Legacy deletion fails closed before any data changes when native membership
-- exists. A truly legacy-only account retains the old legacy cleanup behavior.
select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
do $$
begin
  begin
    perform public.delete_user_account();
    raise exception 'legacy deletion unexpectedly accepted a native member';
  exception when raise_exception then
    if sqlerrm <> 'native_account_deletion_required' then raise; end if;
  end;
  if not exists (select 1 from public.rounds where id = '74000000-0000-4000-8000-000000000002') then
    raise exception 'failed-closed legacy deletion removed native data';
  end if;
end
$$;

insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, status, created_by
) values (
  '77000000-0000-4000-8000-000000000001', 'Legacy Delete',
  '2026-05-01T12:00:00Z', 9, 'ride', 'open',
  '71000000-0000-4000-8000-000000000004'
);
insert into public.round_responses (round_id, user_id, response)
values ('77000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000004', 'yes')
on conflict (round_id, user_id) do nothing;
select set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000004', true);
select public.delete_user_account();
do $$
begin
  if exists (select 1 from public.rounds where id = '77000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.profiles where id = '71000000-0000-4000-8000-000000000004') then
    raise exception 'legacy-only cleanup no longer works';
  end if;
end
$$;

rollback;
