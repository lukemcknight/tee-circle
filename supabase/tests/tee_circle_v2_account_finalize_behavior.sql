-- finalize_account_deletion_v1 regression: active ownership fails closed,
-- owned finished trips are fully erased, surviving groups keep their seats,
-- scores, invites and entitlements, and the auth.users row is deletable
-- afterward with no FK wall. Run only against the disposable fixture through
-- run-local-v2.sh.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

insert into auth.users (id) values
  ('81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-8000-000000000002');

insert into public.profiles (id, full_name) values
  ('81000000-0000-4000-8000-000000000001', 'Deleting User'),
  ('81000000-0000-4000-8000-000000000002', 'Surviving Owner');

-- Trip 1: owned + completed (erased entirely). Trip 2: owned by the survivor;
-- the deleting user claimed a seat, created its round (pre-ownership-transfer
-- shape), typed a score, minted the invite, and bought the unlock. Trip 3:
-- owned + live (the active-ownership blocker).
insert into public.trips (id, public_id, owner_id, name, starts_on, ends_on, status) values
  ('82000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000011',
   '81000000-0000-4000-8000-000000000001', 'Finished Owned Trip', '2026-06-01', '2026-06-02', 'completed'),
  ('82000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000012',
   '81000000-0000-4000-8000-000000000002', 'Surviving Trip', '2026-08-01', '2026-08-02', 'live'),
  ('82000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000013',
   '81000000-0000-4000-8000-000000000001', 'Blocking Live Trip', '2026-09-01', '2026-09-02', 'live');

insert into public.trip_players (id, trip_id, claimed_user_id, display_name, role, rsvp) values
  ('83000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'Old Captain', 'captain', 'yes'),
  ('83000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000002', 'Old Guest', 'player', 'yes'),
  ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000002', 'New Captain', 'captain', 'yes'),
  ('83000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', 'Departing Scorer', 'scorer', 'yes'),
  ('83000000-0000-4000-8000-000000000005', '82000000-0000-4000-8000-000000000003', '81000000-0000-4000-8000-000000000001', 'Blocking Captain', 'captain', 'yes');

insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, status, created_by,
  trip_id, trip_order, public_id, trip_round_status
) values
  ('84000000-0000-4000-8000-000000000001', 'Old Course', '2026-06-01T12:00:00Z', 9, 'ride', 'open',
   '81000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', 1,
   '84000000-0000-4000-8000-000000000011', 'completed'),
  ('84000000-0000-4000-8000-000000000002', 'Surviving Course', '2026-08-01T12:00:00Z', 9, 'ride', 'open',
   '81000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002', 1,
   '84000000-0000-4000-8000-000000000012', 'live');

insert into public.round_holes (round_id, hole_number, par, stroke_index, yards)
select round_id, hole, 4, hole, 300 + hole
from (
  values
    ('84000000-0000-4000-8000-000000000001'::uuid),
    ('84000000-0000-4000-8000-000000000002'::uuid)
) rounds(round_id)
cross join generate_series(1, 9) hole;

insert into public.trip_round_players (round_id, trip_player_id) values
  ('84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000001'),
  ('84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002'),
  ('84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003'),
  ('84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000004');

insert into public.trip_hole_scores (
  id, trip_id, round_id, trip_player_id, hole_number, strokes, penalties,
  recorded_by_user_id, revision, idempotency_key
) values
  ('85000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002',
   1, 5, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000011'),
  ('85000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002',
   '84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003',
   1, 4, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000012');

insert into public.trip_score_audit (
  score_id, trip_id, round_id, trip_player_id, hole_number, strokes,
  penalties, actor_user_id, revision, idempotency_key
) values
  ('85000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002',
   1, 5, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000013'),
  ('85000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002',
   '84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003',
   1, 4, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000014');

insert into public.trip_invites (id, trip_id, token_hash, created_by) values
  ('86000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001',
   '\x01'::bytea, '81000000-0000-4000-8000-000000000001'),
  ('86000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002',
   '\x02'::bytea, '81000000-0000-4000-8000-000000000001');

insert into public.trip_purchase_intents (
  id, trip_id, user_id, status, revenuecat_transaction_id, verified_at
) values (
  '87000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000001', 'verified', 'txn-surviving-unlock', now()
);

insert into public.trip_entitlements (
  trip_id, purchase_intent_id, product_id, revenuecat_transaction_id, verified_at
) values (
  '82000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000001',
  'com.teecircle.app.trip_unlock_2999', 'txn-surviving-unlock', now()
);

insert into public.trip_leaderboard_snapshots (trip_id, revision, scoring_engine_version, payload)
values ('82000000-0000-4000-8000-000000000001', 1, 'test', '{"schemaVersion": 1}'::jsonb);

insert into public.extension_sessions (
  id, trip_id, user_id, trip_player_id, device_id, token_hash, expires_at
) values (
  '88000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000004',
  'delete-device-1', '\x03'::bytea, now() + interval '1 hour'
);

insert into public.native_device_tokens (user_id, device_id, token, environment, bundle_id)
values ('81000000-0000-4000-8000-000000000001', 'delete-device-1', repeat('ab', 16), 'sandbox', 'com.teecircle.app');

insert into public.live_activity_subscriptions (trip_id, user_id, device_id, activity_id, push_token, environment)
values ('82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001',
        'delete-device-1', 'activity-1', repeat('cd', 16), 'sandbox');

insert into tee_internal.command_idempotency (user_id, idempotency_key, operation, request_hash, response)
values ('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001',
        'create_trip_v1', '\x00'::bytea, '{}'::jsonb);

insert into public.course_cards (id, owner_id, name, course_name, hole_count)
values ('8a000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001',
        'My Card', 'My Course', 9);
insert into public.course_card_holes (course_card_id, hole_number, par)
select '8a000000-0000-4000-8000-000000000001', hole, 4 from generate_series(1, 9) hole;

insert into public.rounds (id, course_name, tee_time, holes, walk_ride, status, created_by)
values ('8b000000-0000-4000-8000-000000000001', 'Legacy Course', '2026-05-01T12:00:00Z',
        9, 'ride', 'open', '81000000-0000-4000-8000-000000000001');
insert into public.round_responses (round_id, user_id, response)
values ('8b000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'yes')
on conflict (round_id, user_id) do nothing;

select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);

-- Active ownership fails closed before any mutation.
do $$
declare result jsonb;
begin
  result := public.finalize_account_deletion_v1();
  if result#>>'{error,code}' <> 'account_deletion_blocked' then
    raise exception 'active owned trip did not block deletion: %', result;
  end if;
  if not exists (select 1 from public.trips where id = '82000000-0000-4000-8000-000000000001')
     or exists (
       select 1 from public.trip_players
       where id = '83000000-0000-4000-8000-000000000004' and claimed_user_id is null
     ) then
    raise exception 'blocked finalize mutated data';
  end if;
end
$$;

update public.trips set status = 'completed'
where id = '82000000-0000-4000-8000-000000000003';

-- The full pass: erase owned trips, detach from the surviving group.
do $$
declare result jsonb;
begin
  result := public.finalize_account_deletion_v1();
  if result#>>'{data,finalized}' <> 'true'
     or (result#>>'{data,deletedOwnedTrips}')::int <> 2 then
    raise exception 'finalize did not succeed: %', result;
  end if;
  if exists (select 1 from public.trips where owner_id = '81000000-0000-4000-8000-000000000001')
     or not exists (select 1 from public.trips where id = '82000000-0000-4000-8000-000000000002') then
    raise exception 'owned-trip erasure/survival invariant failed';
  end if;
  if (select claimed_user_id from public.trip_players where id = '83000000-0000-4000-8000-000000000004') is not null
     or (select display_name from public.trip_players where id = '83000000-0000-4000-8000-000000000004') <> 'Departing Scorer'
     or (select rsvp from public.trip_players where id = '83000000-0000-4000-8000-000000000004') <> 'yes' then
    raise exception 'surviving seat was not released cleanly';
  end if;
  if (select recorded_by_user_id from public.trip_hole_scores where id = '85000000-0000-4000-8000-000000000002')
       <> '81000000-0000-4000-8000-000000000002'
     or (select actor_user_id from public.trip_score_audit where score_id = '85000000-0000-4000-8000-000000000002')
       <> '81000000-0000-4000-8000-000000000002' then
    raise exception 'surviving score/audit were not reattributed to the owner';
  end if;
  if (select created_by from public.rounds where id = '84000000-0000-4000-8000-000000000002') is not null then
    raise exception 'surviving native round kept a deleted author';
  end if;
  if (select created_by from public.trip_invites where id = '86000000-0000-4000-8000-000000000002')
       <> '81000000-0000-4000-8000-000000000002'
     or not exists (select 1 from public.trip_entitlements where trip_id = '82000000-0000-4000-8000-000000000002')
     or (select user_id from public.trip_purchase_intents where id = '87000000-0000-4000-8000-000000000001')
       <> '81000000-0000-4000-8000-000000000002' then
    raise exception 'surviving invite/purchase graph broke';
  end if;
  if exists (select 1 from public.course_cards where owner_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.native_device_tokens where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.extension_sessions where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.live_activity_subscriptions where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from tee_internal.command_idempotency where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.rounds where id = '8b000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.profiles where id = '81000000-0000-4000-8000-000000000001') then
    raise exception 'personal artifacts survived finalize';
  end if;
end
$$;

-- The whole point: after the SQL pass, the Auth Admin deletion (Task 4's
-- service-role step) cannot hit a foreign-key wall, and the surviving
-- group's data outlives it.
delete from auth.users where id = '81000000-0000-4000-8000-000000000001';

do $$
begin
  if exists (select 1 from auth.users where id = '81000000-0000-4000-8000-000000000001')
     or not exists (select 1 from public.trip_players where id = '83000000-0000-4000-8000-000000000004')
     or not exists (select 1 from public.trip_hole_scores where id = '85000000-0000-4000-8000-000000000002') then
    raise exception 'auth-user deletion failed or nuked surviving group data';
  end if;
end
$$;

rollback;
