-- Fail-closed authorization and nullable-input checks for native commands.
-- Run after the verified legacy fixture and every ordered v2 migration.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';
update tee_internal.runtime_flags set enabled = false
where key = 'purchases_required';

insert into auth.users (id) values
  ('b1000000-0000-4000-8000-000000000001'),
  ('b1000000-0000-4000-8000-000000000002'),
  ('b1000000-0000-4000-8000-000000000003');

insert into public.profiles (id, full_name, username) values
  ('b1000000-0000-4000-8000-000000000001', 'Boundary Captain', 'boundary-captain'),
  ('b1000000-0000-4000-8000-000000000002', 'Boundary Outsider', 'boundary-outsider'),
  ('b1000000-0000-4000-8000-000000000003', 'Boundary Player', 'boundary-player');

insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, timezone,
  status, enabled_formats, primary_format, scoring_mode, score_revision
) values (
  'b2000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000002',
  'b1000000-0000-4000-8000-000000000001',
  'Boundary Trip', '2026-09-01', '2026-09-01', 'America/New_York',
  'draft', array['stableford']::text[], 'stableford', 'gross', 0
);

insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp, handicap_snapshot
) values
  (
    'b2100000-0000-4000-8000-000000000001',
    'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001',
    'Boundary Captain', 'captain', 'yes', 4.2
  ),
  (
    'b2100000-0000-4000-8000-000000000002',
    'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000003',
    'Boundary Player', 'player', 'yes', 8.1
  ),
  (
    'b2100000-0000-4000-8000-000000000003',
    'b2000000-0000-4000-8000-000000000001',
    null,
    'Boundary Open Seat', 'player', 'pending', null
  );

insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, created_by,
  trip_id, trip_order, public_id, trip_round_status
) values (
  'b2200000-0000-4000-8000-000000000001',
  'Boundary Club', '2026-09-01T09:00:00-04:00', 9, 'ride', null,
  'b2000000-0000-4000-8000-000000000001', 1,
  'b2200000-0000-4000-8000-000000000002', 'scheduled'
);

insert into public.trip_round_players (
  round_id, trip_player_id, course_handicap, playing_handicap, status
) values (
  'b2200000-0000-4000-8000-000000000001',
  'b2100000-0000-4000-8000-000000000002',
  8, 8, 'active'
);

insert into public.trip_invites (
  id, trip_id, token_hash, created_by
) values (
  'b2300000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000001',
  extensions.digest(convert_to('boundary-invite', 'UTF8'), 'sha256'),
  'b1000000-0000-4000-8000-000000000001'
);

-- Deleting a native trip must never orphan its round into the legacy surface.
do $$
declare
  v_blocked boolean := false;
begin
  begin
    delete from public.trips
    where id = 'b2000000-0000-4000-8000-000000000001';
  exception when foreign_key_violation then
    v_blocked := true;
  end;
  if not v_blocked
     or not exists (
       select 1 from public.rounds r
       where r.id = 'b2200000-0000-4000-8000-000000000001'
         and r.trip_id = 'b2000000-0000-4000-8000-000000000001'
     ) then
    raise exception 'native round FK did not restrict trip deletion';
  end if;
end
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'b1000000-0000-4000-8000-000000000002',
  true
);

-- Knowing another user's UUIDs must not turn a missing membership row into
-- captain authority. Every final authenticated captain command is exercised.
do $$
declare
  v_result jsonb;
begin
  v_result := public.update_trip_v1(
    'b2000000-0000-4000-8000-000000000001',
    jsonb_build_object('name', 'Outsider Rename'),
    null
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'update_trip_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.add_trip_player_v1(
    'b2000000-0000-4000-8000-000000000001',
    jsonb_build_object('displayName', 'Injected Player'),
    'b2400000-0000-4000-8000-000000000001'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'add_trip_player_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.create_trip_round_v1(
    'b2000000-0000-4000-8000-000000000001',
    jsonb_build_object(
      'courseCardId', 'b2500000-0000-4000-8000-000000000001',
      'teeTime', '2026-09-01T13:00:00-04:00'
    ),
    'b2400000-0000-4000-8000-000000000002'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'create_trip_round_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.set_round_participation_v1(
    'b2200000-0000-4000-8000-000000000001',
    'b2100000-0000-4000-8000-000000000002',
    20::smallint, 20::smallint, 'withdrawn'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'set_round_participation_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.release_trip_player_claim_v1(
    'b2100000-0000-4000-8000-000000000002'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'release_trip_player_claim_v1 accepted another claim: %', v_result;
  end if;

  v_result := public.release_trip_player_claim_v1(
    'b2100000-0000-4000-8000-000000000003'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'release_trip_player_claim_v1 accepted an open foreign seat: %', v_result;
  end if;

  v_result := public.update_trip_player_v1(
    'b2100000-0000-4000-8000-000000000002',
    jsonb_build_object('displayName', 'Outsider Edit')
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'update_trip_player_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.set_trip_status_v1(
    'b2000000-0000-4000-8000-000000000001', 'draft', 'ready'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'set_trip_status_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.update_trip_round_v1(
    'b2200000-0000-4000-8000-000000000001',
    jsonb_build_object('walkRide', 'walk'),
    null
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'update_trip_round_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.delete_trip_round_v1(
    'b2200000-0000-4000-8000-000000000001',
    'b2400000-0000-4000-8000-000000000003',
    null
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'delete_trip_round_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.delete_trip_player_v1(
    'b2100000-0000-4000-8000-000000000002',
    'b2400000-0000-4000-8000-000000000004',
    null
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'delete_trip_player_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.start_trip_v1(
    'b2000000-0000-4000-8000-000000000001', 0
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'start_trip_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.advance_trip_round_v1(
    'b2000000-0000-4000-8000-000000000001',
    'b2200000-0000-4000-8000-000000000001',
    0, false
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'advance_trip_round_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.create_trip_invite_v1(
    'b2000000-0000-4000-8000-000000000001',
    now() + interval '1 day', null,
    'b2400000-0000-4000-8000-000000000005'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'create_trip_invite_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.list_trip_invites_v1(
    'b2000000-0000-4000-8000-000000000001'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'list_trip_invites_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.revoke_trip_invite_v1(
    'b2300000-0000-4000-8000-000000000001'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'revoke_trip_invite_v1 did not reject a non-member: %', v_result;
  end if;

  v_result := public.rotate_trip_invite_v1(
    'b2000000-0000-4000-8000-000000000001',
    now() + interval '2 days', null,
    'b2400000-0000-4000-8000-000000000006'
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'rotate_trip_invite_v1 did not reject a non-member: %', v_result;
  end if;
end
$$;

reset role;

-- The revoked legacy round lifecycle command is still fail-closed if invoked
-- by an owner/internal path with an authenticated outsider identity.
do $$
declare
  v_result jsonb;
begin
  v_result := public.set_trip_round_status_v1(
    'b2200000-0000-4000-8000-000000000001',
    'scheduled', 'live', false
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'set_trip_round_status_v1 did not reject a non-member: %', v_result;
  end if;
end
$$;

-- No captain-only call may mutate even ancillary idempotency or invite state.
do $$
begin
  if (select t.name from public.trips t
      where t.id = 'b2000000-0000-4000-8000-000000000001') <> 'Boundary Trip'
     or (select t.status from public.trips t
         where t.id = 'b2000000-0000-4000-8000-000000000001') <> 'draft'
     or (select t.score_revision from public.trips t
         where t.id = 'b2000000-0000-4000-8000-000000000001') <> 0
     or (select count(*) from public.trip_players tp
         where tp.trip_id = 'b2000000-0000-4000-8000-000000000001') <> 3
     or (select tp.claimed_user_id from public.trip_players tp
         where tp.id = 'b2100000-0000-4000-8000-000000000002')
        is distinct from 'b1000000-0000-4000-8000-000000000003'::uuid
     or (select tp.claimed_user_id from public.trip_players tp
         where tp.id = 'b2100000-0000-4000-8000-000000000003') is not null
     or (select tp.display_name from public.trip_players tp
         where tp.id = 'b2100000-0000-4000-8000-000000000002') <> 'Boundary Player'
     or (select count(*) from public.rounds r
         where r.trip_id = 'b2000000-0000-4000-8000-000000000001') <> 1
     or (select r.walk_ride from public.rounds r
         where r.id = 'b2200000-0000-4000-8000-000000000001') <> 'ride'
     or (select trp.playing_handicap from public.trip_round_players trp
         where trp.round_id = 'b2200000-0000-4000-8000-000000000001'
           and trp.trip_player_id = 'b2100000-0000-4000-8000-000000000002') <> 8
     or (select trp.status from public.trip_round_players trp
         where trp.round_id = 'b2200000-0000-4000-8000-000000000001'
           and trp.trip_player_id = 'b2100000-0000-4000-8000-000000000002') <> 'active'
     or (select i.revoked_at from public.trip_invites i
         where i.id = 'b2300000-0000-4000-8000-000000000001') is not null
     or (select count(*) from public.trip_invites i
         where i.trip_id = 'b2000000-0000-4000-8000-000000000001') <> 1
     or exists (
       select 1 from tee_internal.command_idempotency ci
       where ci.user_id = 'b1000000-0000-4000-8000-000000000002'
     ) then
    raise exception 'a rejected non-member command mutated native state';
  end if;
end
$$;

-- The global native-write kill switch also covers roster-claim release.
update tee_internal.runtime_flags set enabled = false
where key = 'native_writes_enabled';
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'b1000000-0000-4000-8000-000000000003',
  true
);
do $$
declare
  v_result jsonb;
begin
  v_result := public.release_trip_player_claim_v1(
    'b2100000-0000-4000-8000-000000000002'
  );
  if v_result#>>'{error,code}' is distinct from 'native_writes_disabled' then
    raise exception 'claim release ignored native kill switch: %', v_result;
  end if;
end
$$;
reset role;
update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

-- Nullable lifecycle inputs are rejected explicitly and cannot exploit SQL's
-- three-valued boolean semantics.
select set_config(
  'request.jwt.claim.sub',
  'b1000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;
do $$
declare
  v_result jsonb;
begin
  v_result := public.set_trip_status_v1(
    'b2000000-0000-4000-8000-000000000001', null, 'ready'
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_status_transition' then
    raise exception 'set_trip_status_v1 accepted NULL expected status: %', v_result;
  end if;
  v_result := public.set_trip_status_v1(
    'b2000000-0000-4000-8000-000000000001', 'draft', null
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_status_transition' then
    raise exception 'set_trip_status_v1 accepted NULL new status: %', v_result;
  end if;
  v_result := public.advance_trip_round_v1(
    'b2000000-0000-4000-8000-000000000001',
    'b2200000-0000-4000-8000-000000000001',
    0, null
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_request' then
    raise exception 'advance_trip_round_v1 accepted NULL allowIncomplete: %', v_result;
  end if;
  v_result := public.register_device_push_v1(
    'boundary-device-push',
    '00112233445566778899aabbccddeeff',
    'sandbox',
    null
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_bundle_id' then
    raise exception 'register_device_push_v1 accepted NULL bundle: %', v_result;
  end if;
end
$$;
reset role;

do $$
declare
  v_result jsonb;
begin
  v_result := public.set_trip_round_status_v1(
    'b2200000-0000-4000-8000-000000000001', null, 'live', false
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_status_transition' then
    raise exception 'set_trip_round_status_v1 accepted NULL expected status: %', v_result;
  end if;
  v_result := public.set_trip_round_status_v1(
    'b2200000-0000-4000-8000-000000000001', 'scheduled', null, false
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_status_transition' then
    raise exception 'set_trip_round_status_v1 accepted NULL new status: %', v_result;
  end if;
  v_result := public.set_trip_round_status_v1(
    'b2200000-0000-4000-8000-000000000001', 'scheduled', 'live', null
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_request' then
    raise exception 'set_trip_round_status_v1 accepted NULL allowIncomplete: %', v_result;
  end if;
end
$$;

-- A supplied optimistic timestamp conflicts with a malformed NULL stored
-- timestamp instead of silently authorizing an edit or delete.
update public.rounds set native_updated_at = null
where id = 'b2200000-0000-4000-8000-000000000001';
set local role authenticated;
do $$
declare
  v_result jsonb;
begin
  v_result := public.update_trip_round_v1(
    'b2200000-0000-4000-8000-000000000001',
    jsonb_build_object('walkRide', 'walk'),
    now()
  );
  if v_result#>>'{error,code}' is distinct from 'edit_conflict' then
    raise exception 'round edit accepted NULL optimistic timestamp: %', v_result;
  end if;
  v_result := public.delete_trip_round_v1(
    'b2200000-0000-4000-8000-000000000001',
    'b2400000-0000-4000-8000-000000000007',
    now()
  );
  if v_result#>>'{error,code}' is distinct from 'edit_conflict' then
    raise exception 'round delete accepted NULL optimistic timestamp: %', v_result;
  end if;
end
$$;
reset role;
update public.rounds set native_updated_at = now()
where id = 'b2200000-0000-4000-8000-000000000001';

-- Canonical snapshot and worker commands must reject NULL/unbounded inputs.
set local role service_role;
do $$
declare
  v_result jsonb;
  v_allowed boolean;
begin
  v_allowed := public.consume_public_rate_limit_service_v1(
    encode(extensions.digest(convert_to('boundary-rate-limit', 'UTF8'), 'sha256'), 'hex'),
    'boundary-test',
    null,
    60
  );
  if v_allowed is distinct from false then
    raise exception 'rate limiter accepted NULL request limit';
  end if;
  v_result := public.lease_trip_snapshot_jobs_v1(null);
  if v_result#>>'{error,code}' is distinct from 'invalid_limit' then
    raise exception 'snapshot lease accepted NULL limit: %', v_result;
  end if;
  v_result := public.lease_live_activity_deliveries_service_v1(null, null, null);
  if v_result#>>'{error,code}' is distinct from 'invalid_limit' then
    raise exception 'Live Activity lease accepted NULL limit: %', v_result;
  end if;
  v_result := public.complete_live_activity_delivery_service_v1(
    null, null, null, null, null
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_request' then
    raise exception 'Live Activity completion accepted NULL required values: %', v_result;
  end if;
  v_result := public.persist_trip_snapshot_v1(
    'b2000000-0000-4000-8000-000000000001', 0, '{}'::jsonb,
    'tee-circle-ts-2'
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_snapshot' then
    raise exception 'snapshot persistence accepted missing identity fields: %', v_result;
  end if;
  v_result := public.persist_trip_snapshot_v1(
    'b2000000-0000-4000-8000-000000000001', 0, null,
    'tee-circle-ts-2'
  );
  if v_result#>>'{error,code}' is distinct from 'invalid_snapshot' then
    raise exception 'snapshot persistence accepted NULL payload: %', v_result;
  end if;
  v_result := public.persist_trip_snapshot_v1(
    'b2000000-0000-4000-8000-000000000001', 0,
    jsonb_build_object(
      'schemaVersion', 1,
      'revision', 0,
      'tripId', 'b2000000-0000-4000-8000-000000000002'
    ),
    null
  );
  if v_result#>>'{error,code}' is distinct from 'unsupported_scoring_engine' then
    raise exception 'snapshot persistence accepted NULL engine: %', v_result;
  end if;
end
$$;
reset role;

do $$
begin
  if exists (
    select 1 from public.trip_leaderboard_snapshots s
    where s.trip_id = 'b2000000-0000-4000-8000-000000000001'
  ) or (select tp.claimed_user_id from public.trip_players tp
        where tp.id = 'b2100000-0000-4000-8000-000000000002')
       is distinct from 'b1000000-0000-4000-8000-000000000003'::uuid
     or (select t.status from public.trips t
         where t.id = 'b2000000-0000-4000-8000-000000000001') <> 'draft' then
    raise exception 'nullable-input rejection mutated protected state';
  end if;
end
$$;

-- A malformed NULL round lifecycle closes both authoritative score paths.
update public.trips set status = 'live'
where id = 'b2000000-0000-4000-8000-000000000001';
update public.rounds set trip_round_status = null
where id = 'b2200000-0000-4000-8000-000000000001';
insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, created_by
) values (
  'b2200000-0000-4000-8000-000000000003',
  'Boundary Legacy Club', '2026-09-02T09:00:00-04:00', 9, 'walk',
  'b1000000-0000-4000-8000-000000000001'
);
insert into public.round_holes (round_id, hole_number, par, stroke_index, yards)
values (
  'b2200000-0000-4000-8000-000000000001', 1, 4, 1, 350
);
insert into public.trip_round_players (
  round_id, trip_player_id, course_handicap, playing_handicap, status
) values (
  'b2200000-0000-4000-8000-000000000001',
  'b2100000-0000-4000-8000-000000000001',
  4, 4, 'active'
);
insert into public.extension_sessions (
  id, trip_id, user_id, trip_player_id, device_id, token_hash, expires_at
) values (
  'b2600000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'b2100000-0000-4000-8000-000000000001',
  'boundary-device-0001',
  extensions.digest(convert_to('boundary-extension-session', 'UTF8'), 'sha256'),
  now() + interval '1 day'
);

set local role service_role;
do $$
declare
  v_result jsonb;
begin
  v_result := public.record_extension_hole_score_service_v1(
    encode(extensions.digest(convert_to('boundary-extension-session', 'UTF8'), 'sha256'), 'hex'),
    'b2200000-0000-4000-8000-000000000001',
    null::uuid,
    1::smallint, 4::smallint, 0::smallint,
    'b2700000-0000-4000-8000-000000000003',
    0
  );
  if v_result#>>'{error,code}' is distinct from 'forbidden' then
    raise exception 'Messages score path accepted NULL player identity: %', v_result;
  end if;

  v_result := public.record_extension_hole_score_service_v1(
    encode(extensions.digest(convert_to('boundary-extension-session', 'UTF8'), 'sha256'), 'hex'),
    'b2200000-0000-4000-8000-000000000003',
    'b2100000-0000-4000-8000-000000000001',
    1::smallint, 4::smallint, 0::smallint,
    'b2700000-0000-4000-8000-000000000004',
    0
  );
  if v_result#>>'{error,code}' is distinct from 'round_not_found' then
    raise exception 'Messages score path accepted legacy/NULL trip round: %', v_result;
  end if;

  v_result := public.record_authenticated_hole_score_service_v1(
    'b1000000-0000-4000-8000-000000000001',
    'b2200000-0000-4000-8000-000000000001',
    'b2100000-0000-4000-8000-000000000001',
    1::smallint, 4::smallint, 0::smallint,
    'b2700000-0000-4000-8000-000000000001',
    0
  );
  if v_result#>>'{error,code}' is distinct from 'scoring_closed' then
    raise exception 'authenticated score path accepted NULL round status: %', v_result;
  end if;

  v_result := public.record_extension_hole_score_service_v1(
    encode(extensions.digest(convert_to('boundary-extension-session', 'UTF8'), 'sha256'), 'hex'),
    'b2200000-0000-4000-8000-000000000001',
    'b2100000-0000-4000-8000-000000000001',
    1::smallint, 4::smallint, 0::smallint,
    'b2700000-0000-4000-8000-000000000002',
    0
  );
  if v_result#>>'{error,code}' is distinct from 'scoring_closed' then
    raise exception 'Messages score path accepted NULL round status: %', v_result;
  end if;
end
$$;
reset role;

do $$
begin
  if exists (
    select 1 from public.trip_hole_scores s
    where s.trip_id = 'b2000000-0000-4000-8000-000000000001'
  ) or exists (
    select 1 from public.trip_score_audit a
    where a.trip_id = 'b2000000-0000-4000-8000-000000000001'
  ) or (select t.score_revision from public.trips t
        where t.id = 'b2000000-0000-4000-8000-000000000001') <> 0 then
    raise exception 'closed score paths mutated authoritative score state';
  end if;
end
$$;

rollback;
