-- Release-blocker regression coverage for migration 011. Run only against the
-- disposable verified fixture through run-local-v2.sh.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';
update tee_internal.runtime_flags set enabled = false
where key = 'purchases_required';

insert into auth.users (id) values
  ('81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-8000-000000000002'),
  ('81000000-0000-4000-8000-000000000003');
insert into public.profiles (id, full_name) values
  ('81000000-0000-4000-8000-000000000001', 'Integrity Captain'),
  ('81000000-0000-4000-8000-000000000002', 'Integrity Player'),
  ('81000000-0000-4000-8000-000000000003', 'Integrity Other');

-- A 9-hole card cannot use the 18-hole stroke-index range.
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
do $$
declare result jsonb;
begin
  result := public.create_course_card_v1(
    jsonb_build_object(
      'name', 'Bad nine',
      'courseName', 'Bounds Club',
      'holes', (
        select jsonb_agg(jsonb_build_object(
          'holeNumber', hole,
          'par', 4,
          'strokeIndex', hole + 9
        ) order by hole)
        from generate_series(1, 9) hole
      )
    ),
    '81500000-0000-4000-8000-000000000001'
  );
  if result#>>'{error,code}' <> 'invalid_course_card' then
    raise exception '9-hole stroke indexes above nine were accepted: %', result;
  end if;
  if exists (select 1 from public.course_cards where name = 'Bad nine') then
    raise exception 'invalid 9-hole card was partially persisted';
  end if;
end
$$;

-- Extension credentials are unique per user/device/trip, not globally per
-- device. Reissuing one trip must leave the other trip connected.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status,
  enabled_formats, primary_format, scoring_mode
) values
  ('82000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000011', '81000000-0000-4000-8000-000000000001', 'Session One', '2026-08-01', '2026-08-01', 'draft', array['stableford'], 'stableford', 'gross'),
  ('82000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000012', '81000000-0000-4000-8000-000000000001', 'Session Two', '2026-08-02', '2026-08-02', 'draft', array['stableford'], 'stableford', 'gross');
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values
  ('82100000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes'),
  ('82100000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes');

do $$
declare first_result jsonb; second_result jsonb; replacement jsonb;
begin
  first_result := public.issue_extension_session_v1(
    '82000000-0000-4000-8000-000000000001', 'integrity-device-001'
  );
  second_result := public.issue_extension_session_v1(
    '82000000-0000-4000-8000-000000000002', 'integrity-device-001'
  );
  replacement := public.issue_extension_session_v1(
    '82000000-0000-4000-8000-000000000001', 'integrity-device-001'
  );
  if first_result ? 'error' or second_result ? 'error' or replacement ? 'error' then
    raise exception 'extension issuance failed: %, %, %', first_result, second_result, replacement;
  end if;
  if (select count(*) from public.extension_sessions
      where user_id = '81000000-0000-4000-8000-000000000001'
        and device_id = 'integrity-device-001' and revoked_at is null) <> 2
     or (select count(*) from public.extension_sessions
         where trip_id = '82000000-0000-4000-8000-000000000001'
           and user_id = '81000000-0000-4000-8000-000000000001'
           and device_id = 'integrity-device-001' and revoked_at is null) <> 1
     or (select count(*) from public.extension_sessions
         where trip_id = '82000000-0000-4000-8000-000000000002'
           and user_id = '81000000-0000-4000-8000-000000000001'
           and device_id = 'integrity-device-001' and revoked_at is null) <> 1 then
    raise exception 'extension issuance revoked the wrong trip or left duplicates';
  end if;
end
$$;

-- Canonical input exposes the actual round length and preserves played strokes
-- separately from additive penalties. Conflicts report the current target-hole
-- value, including an explicit null when no score exists.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status,
  enabled_formats, primary_format, scoring_mode, score_revision
) values (
  '83000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Scoring Integrity', '2026-08-03', '2026-08-03', 'live',
  array['stableford'], 'stableford', 'gross', 0
);
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values
  ('83100000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes'),
  ('83100000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000002', 'Player', 'player', 'yes');
insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, created_by,
  trip_id, trip_order, public_id, trip_round_status
) values (
  '83200000-0000-4000-8000-000000000001', 'Penalty Club',
  '2026-08-03T12:00:00Z', 9, 'ride', '81000000-0000-4000-8000-000000000001',
  '83000000-0000-4000-8000-000000000001', 1,
  '83200000-0000-4000-8000-000000000011', 'live'
);

-- Expo keeps direct access to legacy rounds, but that surface must never
-- insert, edit, or delete a row attached to a native trip. The legacy
-- SECURITY DEFINER delete RPC is guarded separately because it bypasses RLS.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
do $$
declare
  insert_blocked boolean := false;
  affected bigint;
  legacy_id uuid := '83200000-0000-4000-8000-000000000099';
begin
  begin
    insert into public.rounds (
      id, course_name, tee_time, holes, walk_ride, created_by,
      trip_id, trip_order, public_id, trip_round_status
    ) values (
      '83200000-0000-4000-8000-000000000002', 'Injected Native Round',
      '2026-08-03T14:00:00Z', 9, 'ride', auth.uid(),
      '83000000-0000-4000-8000-000000000001', 2,
      '83200000-0000-4000-8000-000000000012', 'scheduled'
    );
  exception when insufficient_privilege then
    insert_blocked := true;
  end;
  if not insert_blocked then
    raise exception 'legacy direct insert attached a round to a native trip';
  end if;

  update public.rounds set course_name = 'Mutated Native Round'
  where id = '83200000-0000-4000-8000-000000000001';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'legacy direct update mutated a native round';
  end if;

  delete from public.rounds
  where id = '83200000-0000-4000-8000-000000000001';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'legacy direct delete removed a native round';
  end if;
  if public.delete_round('83200000-0000-4000-8000-000000000001') then
    raise exception 'legacy delete RPC removed a native round';
  end if;

  insert into public.rounds (
    id, course_name, tee_time, holes, walk_ride, created_by
  ) values (
    legacy_id, 'Legacy Compatibility Round', '2026-08-04T12:00:00Z',
    9, 'ride', auth.uid()
  );
  update public.rounds set course_name = 'Legacy Round Updated' where id = legacy_id;
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'production legacy rounds unexpectedly allow direct updates';
  end if;
  if not public.delete_round(legacy_id) then
    raise exception 'legacy trip_id-null round compatibility was broken';
  end if;
end
$$;
reset role;

insert into public.round_holes (round_id, hole_number, par, stroke_index)
select '83200000-0000-4000-8000-000000000001', hole, 4, hole
from generate_series(1, 9) hole;
insert into public.trip_round_players (
  round_id, trip_player_id, course_handicap, playing_handicap, status
) values
  ('83200000-0000-4000-8000-000000000001', '83100000-0000-4000-8000-000000000001', 0, 0, 'active'),
  ('83200000-0000-4000-8000-000000000001', '83100000-0000-4000-8000-000000000002', 0, 0, 'active');

create temporary table release_integrity_state (key text primary key, value text not null);
do $$
declare accepted jsonb; conflict jsonb; empty_conflict jsonb; scoring_input jsonb; session_result jsonb;
begin
  accepted := public.record_authenticated_hole_score_service_v1(
    '81000000-0000-4000-8000-000000000002',
    '83200000-0000-4000-8000-000000000001',
    '83100000-0000-4000-8000-000000000002',
    1::smallint, 4::smallint, 2::smallint,
    '83500000-0000-4000-8000-000000000001', 0
  );
  if accepted#>>'{data,acceptedRevision}' <> '1'
     or accepted#>>'{data,score,strokes}' <> '4'
     or accepted#>>'{data,score,penalties}' <> '2'
     or accepted#>>'{data,score,grossTotal}' <> '6' then
    raise exception 'additive penalty score failed: %', accepted;
  end if;
  if (select (strokes, penalties) from public.trip_hole_scores
      where round_id = '83200000-0000-4000-8000-000000000001'
        and trip_player_id = '83100000-0000-4000-8000-000000000002'
        and hole_number = 1) <> row(4::smallint, 2::smallint) then
    raise exception 'persisted score did not keep strokes and penalties separate';
  end if;

  conflict := public.record_authenticated_hole_score_service_v1(
    '81000000-0000-4000-8000-000000000002',
    '83200000-0000-4000-8000-000000000001',
    '83100000-0000-4000-8000-000000000002',
    1::smallint, 5::smallint, 0::smallint,
    '83500000-0000-4000-8000-000000000002', 0
  );
  if conflict#>>'{error,code}' <> 'score_conflict'
     or conflict#>>'{error,details,currentScore,strokes}' <> '4'
     or conflict#>>'{error,details,currentScore,penalties}' <> '2'
     or conflict#>>'{error,details,currentScore,revision}' <> '1' then
    raise exception 'existing score conflict details failed: %', conflict;
  end if;

  empty_conflict := public.record_authenticated_hole_score_service_v1(
    '81000000-0000-4000-8000-000000000002',
    '83200000-0000-4000-8000-000000000001',
    '83100000-0000-4000-8000-000000000002',
    2::smallint, 4::smallint, 0::smallint,
    '83500000-0000-4000-8000-000000000003', 0
  );
  if empty_conflict#>>'{error,code}' <> 'score_conflict'
     or not (empty_conflict#>'{error,details}' ? 'currentScore')
     or empty_conflict#>'{error,details,currentScore}' <> 'null'::jsonb then
    raise exception 'empty score conflict did not preserve explicit null: %', empty_conflict;
  end if;

  scoring_input := public.get_trip_scoring_input_v1(
    '83000000-0000-4000-8000-000000000001', 1
  );
  if scoring_input#>>'{data,rounds,0,holeCount}' <> '9'
     or scoring_input#>>'{data,rounds,0,players,1,holes,0,strokes}' <> '4'
     or scoring_input#>>'{data,rounds,0,players,1,holes,0,penalties}' <> '2'
     or scoring_input#>>'{data,rounds,0,players,1,holes,1,penalties}' <> '0' then
    raise exception 'canonical scoring input omitted hole count or penalties: %', scoring_input;
  end if;

  perform set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000002', true);
  session_result := public.issue_extension_session_v1(
    '83000000-0000-4000-8000-000000000001', 'integrity-score-device'
  );
  if session_result ? 'error' then raise exception 'score extension session failed: %', session_result; end if;
  insert into release_integrity_state values (
    'score_session_hash',
    encode(extensions.digest(convert_to(session_result#>>'{data,sessionToken}', 'UTF8'), 'sha256'), 'hex')
  );
end
$$;

do $$
declare result jsonb; token_hash text;
begin
  select value into token_hash from release_integrity_state where key = 'score_session_hash';
  result := public.record_extension_hole_score_service_v1(
    token_hash,
    '83200000-0000-4000-8000-000000000001',
    '83100000-0000-4000-8000-000000000002',
    1::smallint, 5::smallint, 1::smallint,
    '83500000-0000-4000-8000-000000000004', 0
  );
  if result#>>'{error,code}' <> 'score_conflict'
     or result#>>'{error,details,currentScore,strokes}' <> '4'
     or result#>>'{error,details,currentScore,penalties}' <> '2'
     or result#>>'{error,details,currentScore,revision}' <> '1' then
    raise exception 'extension conflict details failed: %', result;
  end if;
end
$$;

-- Revoking a roster claim also ends its Messages/ActivityKit credentials, and
-- a stale score request from that former member cannot learn current values.
do $$
declare activity_result jsonb; release_result jsonb; rejected jsonb;
begin
  activity_result := public.register_live_activity_v1(
    '83000000-0000-4000-8000-000000000001', 'integrity-revoked-device',
    'integrity-revoked-activity', repeat('c', 64), 'sandbox', null
  );
  if activity_result ? 'error' then
    raise exception 'revocation activity setup failed: %', activity_result;
  end if;
  perform set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
  release_result := public.release_trip_player_claim_v1(
    '83100000-0000-4000-8000-000000000002'
  );
  if release_result ? 'error'
     or not exists (
       select 1 from public.live_activity_subscriptions
       where activity_id = 'integrity-revoked-activity' and ended_at is not null
     ) then
    raise exception 'claim release did not terminate delivery credentials: %', release_result;
  end if;
  rejected := public.record_authenticated_hole_score_service_v1(
    '81000000-0000-4000-8000-000000000002',
    '83200000-0000-4000-8000-000000000001',
    '83100000-0000-4000-8000-000000000002',
    1::smallint, 7::smallint, 0::smallint,
    '83500000-0000-4000-8000-000000000005', 0
  );
  if rejected#>>'{error,code}' <> 'forbidden'
     or rejected#>'{error}' ? 'currentRevision'
     or rejected#>'{error}' ? 'details' then
    raise exception 'revoked score request leaked conflict state: %', rejected;
  end if;
end
$$;

-- Starting and advancing a trip changes trip+round state and revision in one
-- transaction. The former two-step status command rejects the live boundary.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status,
  enabled_formats, primary_format, scoring_mode, score_revision
) values (
  '84000000-0000-4000-8000-000000000001',
  '84000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Lifecycle Integrity', '2026-08-04', '2026-08-05', 'ready',
  array['stableford'], 'stableford', 'gross', 0
);
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values
  ('84100000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes'),
  ('84100000-0000-4000-8000-000000000002', '84000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000002', 'Player', 'player', 'yes');
insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, created_by,
  trip_id, trip_order, public_id, trip_round_status
) values
  ('84200000-0000-4000-8000-000000000001', 'Lifecycle One', '2026-08-04T12:00:00Z', 9, 'ride', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', 1, '84200000-0000-4000-8000-000000000011', 'scheduled'),
  ('84200000-0000-4000-8000-000000000002', 'Lifecycle Two', '2026-08-05T12:00:00Z', 9, 'ride', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', 2, '84200000-0000-4000-8000-000000000012', 'scheduled');
insert into public.round_holes (round_id, hole_number, par, stroke_index)
select round_id, hole, 4, hole
from (values
  ('84200000-0000-4000-8000-000000000001'::uuid),
  ('84200000-0000-4000-8000-000000000002'::uuid)
) rounds(round_id)
cross join generate_series(1, 9) hole;
insert into public.trip_round_players (
  round_id, trip_player_id, course_handicap, playing_handicap, status
)
select r.id, p.id, 0, 0, 'active'
from public.rounds r
cross join public.trip_players p
where r.trip_id = '84000000-0000-4000-8000-000000000001'
  and p.trip_id = r.trip_id;

select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
do $$
declare old_result jsonb; started jsonb; advanced jsonb; completed jsonb;
  closed_round_score jsonb;
begin
  old_result := public.set_trip_status_v1(
    '84000000-0000-4000-8000-000000000001', 'ready', 'live'
  );
  if old_result#>>'{error,code}' <> 'atomic_lifecycle_required' then
    raise exception 'old trip start command remains non-atomic: %', old_result;
  end if;
  started := public.start_trip_v1('84000000-0000-4000-8000-000000000001', 0);
  if started#>>'{data,tripStatus}' <> 'live'
     or started#>>'{data,currentRoundId}' <> '84200000-0000-4000-8000-000000000001'
     or started#>>'{data,scoreRevision}' <> '1'
     or (select count(*) from public.rounds
         where trip_id = '84000000-0000-4000-8000-000000000001'
           and trip_round_status = 'live') <> 1 then
    raise exception 'atomic trip start failed: %', started;
  end if;

  advanced := public.advance_trip_round_v1(
    '84000000-0000-4000-8000-000000000001',
    '84200000-0000-4000-8000-000000000001', 1, true
  );
  if advanced#>>'{data,tripStatus}' <> 'live'
     or advanced#>>'{data,nextRoundId}' <> '84200000-0000-4000-8000-000000000002'
     or advanced#>>'{data,scoreRevision}' <> '2'
     or (select trip_round_status from public.rounds where id = '84200000-0000-4000-8000-000000000001') <> 'completed'
     or (select trip_round_status from public.rounds where id = '84200000-0000-4000-8000-000000000002') <> 'live' then
    raise exception 'atomic round advance failed: %', advanced;
  end if;

  closed_round_score := public.record_authenticated_hole_score_service_v1(
    '81000000-0000-4000-8000-000000000002',
    '84200000-0000-4000-8000-000000000001',
    '84100000-0000-4000-8000-000000000002',
    1::smallint, 4::smallint, 0::smallint,
    '84500000-0000-4000-8000-000000000001', 2
  );
  if closed_round_score#>>'{error,code}' <> 'scoring_closed' then
    raise exception 'completed prior round accepted a late score: %', closed_round_score;
  end if;

  completed := public.advance_trip_round_v1(
    '84000000-0000-4000-8000-000000000001',
    '84200000-0000-4000-8000-000000000002', 2, true
  );
  if completed#>>'{data,tripStatus}' <> 'completed'
     or completed#>>'{data,scoreRevision}' <> '3'
     or completed#>'{data,nextRoundId}' <> 'null'::jsonb
     or (select status from public.trips where id = '84000000-0000-4000-8000-000000000001') <> 'completed'
     or exists (select 1 from public.rounds
                where trip_id = '84000000-0000-4000-8000-000000000001'
                  and trip_round_status <> 'completed') then
    raise exception 'atomic final completion failed: %', completed;
  end if;
end
$$;

-- Different idempotency keys reuse the one pending purchase intent.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on
) values (
  '85000000-0000-4000-8000-000000000001',
  '85000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Purchase Integrity', '2026-08-06', '2026-08-06'
);
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values
  ('85010000-0000-4000-8000-000000000001', '85000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'Old Captain', 'captain', 'yes'),
  ('85010000-0000-4000-8000-000000000002', '85000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000003', 'New Captain', 'player', 'yes');
do $$
declare first_result jsonb; second_result jsonb; transfer_result jsonb; new_owner_result jsonb;
begin
  first_result := public.create_trip_purchase_intent_v1(
    '85000000-0000-4000-8000-000000000001',
    '85100000-0000-4000-8000-000000000001'
  );
  second_result := public.create_trip_purchase_intent_v1(
    '85000000-0000-4000-8000-000000000001',
    '85100000-0000-4000-8000-000000000002'
  );
  if first_result#>>'{data,reusedPending}' <> 'false'
     or second_result#>>'{data,reusedPending}' <> 'true'
     or first_result#>>'{data,purchaseIntentId}' <> second_result#>>'{data,purchaseIntentId}'
     or (select count(*) from public.trip_purchase_intents
         where trip_id = '85000000-0000-4000-8000-000000000001'
           and status = 'pending') <> 1 then
    raise exception 'pending purchase intent was ambiguous: %, %', first_result, second_result;
  end if;
  transfer_result := public.transfer_trip_ownership_v1(
    '85000000-0000-4000-8000-000000000001',
    '85010000-0000-4000-8000-000000000002'
  );
  if transfer_result#>>'{error,code}' <> 'purchase_pending'
     or transfer_result#>>'{error,details,purchaseIntentId}' <> first_result#>>'{data,purchaseIntentId}'
     or (select status from public.trip_purchase_intents
         where id = (first_result#>>'{data,purchaseIntentId}')::uuid) <> 'pending'
     or (select owner_id from public.trips
         where id = '85000000-0000-4000-8000-000000000001')
        <> '81000000-0000-4000-8000-000000000001'::uuid then
    raise exception 'ownership transfer did not block the in-flight purchase: %', transfer_result;
  end if;
  update public.trip_purchase_intents set status = 'cancelled'
  where id = (first_result#>>'{data,purchaseIntentId}')::uuid;
  transfer_result := public.transfer_trip_ownership_v1(
    '85000000-0000-4000-8000-000000000001',
    '85010000-0000-4000-8000-000000000002'
  );
  if transfer_result ? 'error' then
    raise exception 'ownership transfer failed after purchase cancellation: %', transfer_result;
  end if;
  perform set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000003', true);
  new_owner_result := public.create_trip_purchase_intent_v1(
    '85000000-0000-4000-8000-000000000001',
    '85100000-0000-4000-8000-000000000003'
  );
  if new_owner_result#>>'{data,reusedPending}' <> 'false'
     or new_owner_result#>>'{data,purchaseIntentId}' = first_result#>>'{data,purchaseIntentId}'
     or (select user_id from public.trip_purchase_intents
         where id = (new_owner_result#>>'{data,purchaseIntentId}')::uuid)
        <> '81000000-0000-4000-8000-000000000003'::uuid then
    raise exception 'new captain reused the old captain purchase: %', new_owner_result;
  end if;
  perform set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
end
$$;

-- Ready trips can be shared before the asynchronous initial snapshot exists,
-- but the bearer plaintext is returned only on the first command response.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status
) values (
  '88000000-0000-4000-8000-000000000001',
  '88000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Invite One Shot', '2026-08-09', '2026-08-09', 'ready'
);
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values (
  '88100000-0000-4000-8000-000000000001',
  '88000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  'Captain', 'captain', 'yes'
);
select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
do $$
declare first_result jsonb; replay_result jsonb; stored jsonb;
  expiry timestamptz := now() + interval '1 day';
begin
  if exists (
    select 1 from public.trip_leaderboard_snapshots
    where trip_id = '88000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'invite race fixture unexpectedly has a snapshot';
  end if;
  first_result := public.create_trip_invite_v1(
    '88000000-0000-4000-8000-000000000001', expiry, null,
    '88500000-0000-4000-8000-000000000001'
  );
  replay_result := public.create_trip_invite_v1(
    '88000000-0000-4000-8000-000000000001', expiry, null,
    '88500000-0000-4000-8000-000000000001'
  );
  select ci.response into stored
  from tee_internal.command_idempotency ci
  where ci.user_id = '81000000-0000-4000-8000-000000000001'
    and ci.idempotency_key = '88500000-0000-4000-8000-000000000001';
  if first_result#>>'{data,inviteToken}' is null
     or first_result#>>'{data,url}' not like 'https://teecircle.vercel.app/t/%'
     or replay_result#>>'{error,code}' <> 'invite_token_already_issued'
     or stored#>'{data}' ? 'inviteToken'
     or stored#>'{data}' ? 'url'
     or stored::text like '%' || (first_result#>>'{data,inviteToken}') || '%' then
    raise exception 'invite plaintext was persisted/replayed or snapshot race returned: %, %, %',
      first_result, replay_result, stored;
  end if;
end
$$;

do $$
declare listing jsonb; rotated jsonb; replay jsonb; forbidden jsonb;
begin
  listing := public.list_trip_invites_v1('88000000-0000-4000-8000-000000000001');
  if jsonb_array_length(listing#>'{data,invites}') <> 1
     or listing::text like '%tokenHash%'
     or listing::text like '%token_hash%' then
    raise exception 'invite metadata listing is missing or leaks bearer evidence: %', listing;
  end if;
  rotated := public.rotate_trip_invite_v1(
    '88000000-0000-4000-8000-000000000001', null, null,
    '88500000-0000-4000-8000-000000000002'
  );
  replay := public.rotate_trip_invite_v1(
    '88000000-0000-4000-8000-000000000001', null, null,
    '88500000-0000-4000-8000-000000000002'
  );
  listing := public.list_trip_invites_v1('88000000-0000-4000-8000-000000000001');
  if rotated#>>'{data,inviteToken}' is null
     or rotated#>>'{data,url}' not like 'https://teecircle.vercel.app/t/%'
     or replay#>>'{error,code}' <> 'invite_token_already_issued'
     or (select count(*) from jsonb_array_elements(listing#>'{data,invites}') i where i->>'status' = 'active') <> 1
     or (select count(*) from jsonb_array_elements(listing#>'{data,invites}') i where i->>'status' = 'revoked') <> 1 then
    raise exception 'atomic invite rotation failed: %, %, %', rotated, replay, listing;
  end if;

  perform set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000004', true);
  forbidden := public.list_trip_invites_v1('88000000-0000-4000-8000-000000000001');
  if forbidden#>>'{error,code}' <> 'forbidden' then
    raise exception 'noncaptain discovered invite metadata: %', forbidden;
  end if;
  perform set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);
end
$$;

-- RevenueCat provenance keeps TestFlight receipts inert in production,
-- supports explicit cancellation, and repairs a delayed in-window webhook.
-- Exercise these receipt invariants with the production purchase gate enabled;
-- pilot-mode effective unlock behavior is covered in tee_circle_v2_behavior.
update tee_internal.runtime_flags set enabled = true
where key = 'purchases_required';

insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on
) values
  ('88600000-0000-4000-8000-000000000001', '88600000-0000-4000-8000-000000000011', '81000000-0000-4000-8000-000000000001', 'Environment Purchase', '2026-08-10', '2026-08-10'),
  ('88600000-0000-4000-8000-000000000002', '88600000-0000-4000-8000-000000000012', '81000000-0000-4000-8000-000000000001', 'Cancelled Purchase', '2026-08-11', '2026-08-11'),
  ('88600000-0000-4000-8000-000000000003', '88600000-0000-4000-8000-000000000013', '81000000-0000-4000-8000-000000000001', 'Delayed Purchase', '2026-08-12', '2026-08-12');
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values (
  '88700000-0000-4000-8000-000000000001',
  '88600000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  'Captain', 'captain', 'yes'
);
do $$
declare sandbox_intent jsonb; sandbox_claim jsonb; bootstrap jsonb;
  production_intent jsonb; production_claim jsonb;
  cancelled_intent jsonb; cancelled jsonb; cancelled_replay jsonb;
  delayed_intent jsonb; delayed_claim jsonb;
  delayed_id uuid;
begin
  sandbox_intent := public.create_trip_purchase_intent_v1(
    '88600000-0000-4000-8000-000000000001',
    '88800000-0000-4000-8000-000000000001'
  );
  sandbox_claim := public.verify_trip_purchase_v1(
    (sandbox_intent#>>'{data,purchaseIntentId}')::uuid,
    'com.teecircle.app.trip_unlock_2999', 'sandbox-transaction-integrity',
    'sandbox', now(), now()
  );
  bootstrap := public.get_trip_bootstrap_v1('88600000-0000-4000-8000-000000000001');
  if sandbox_claim#>>'{data,unlocked}' <> 'false'
     or bootstrap#>>'{data,trip,isUnlocked}' <> 'false'
     or (select environment from public.trip_entitlements
         where trip_id = '88600000-0000-4000-8000-000000000001') <> 'sandbox' then
    raise exception 'sandbox purchase unlocked production state: %, %', sandbox_claim, bootstrap;
  end if;
  update tee_internal.runtime_flags set enabled = true
  where key = 'sandbox_purchases_enabled';
  bootstrap := public.get_trip_bootstrap_v1('88600000-0000-4000-8000-000000000001');
  if bootstrap#>>'{data,trip,isUnlocked}' <> 'true' then
    raise exception 'TestFlight sandbox flag did not enable sandbox entitlement: %', bootstrap;
  end if;
  update tee_internal.runtime_flags set enabled = false
  where key = 'sandbox_purchases_enabled';

  production_intent := public.create_trip_purchase_intent_v1(
    '88600000-0000-4000-8000-000000000001',
    '88800000-0000-4000-8000-000000000002'
  );
  production_claim := public.verify_trip_purchase_v1(
    (production_intent#>>'{data,purchaseIntentId}')::uuid,
    'com.teecircle.app.trip_unlock_2999', 'production-transaction-integrity',
    'production', now(), now()
  );
  if production_claim#>>'{data,unlocked}' <> 'true'
     or (select environment from public.trip_entitlements
         where trip_id = '88600000-0000-4000-8000-000000000001') <> 'production'
     or (select count(*) from public.trip_entitlements
         where trip_id = '88600000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'production purchase did not replace sandbox provenance: %', production_claim;
  end if;

  cancelled_intent := public.create_trip_purchase_intent_v1(
    '88600000-0000-4000-8000-000000000002',
    '88800000-0000-4000-8000-000000000003'
  );
  cancelled := public.cancel_trip_purchase_intent_v1(
    (cancelled_intent#>>'{data,purchaseIntentId}')::uuid
  );
  cancelled_replay := public.cancel_trip_purchase_intent_v1(
    (cancelled_intent#>>'{data,purchaseIntentId}')::uuid
  );
  if cancelled#>>'{data,status}' <> 'cancelled'
     or cancelled_replay#>>'{data,status}' <> 'cancelled'
     or (select status from public.trip_purchase_intents
         where id = (cancelled_intent#>>'{data,purchaseIntentId}')::uuid) <> 'cancelled' then
    raise exception 'purchase cancellation was not idempotent: %, %', cancelled, cancelled_replay;
  end if;

  delayed_intent := public.create_trip_purchase_intent_v1(
    '88600000-0000-4000-8000-000000000003',
    '88800000-0000-4000-8000-000000000004'
  );
  delayed_id := (delayed_intent#>>'{data,purchaseIntentId}')::uuid;
  update public.trip_purchase_intents
  set status = 'expired',
      created_at = now() - interval '2 hours',
      expires_at = now() - interval '1 hour'
  where id = delayed_id;
  delayed_claim := public.verify_trip_purchase_v1(
    delayed_id,
    'com.teecircle.app.trip_unlock_2999', 'delayed-transaction-integrity',
    'production', now() - interval '90 minutes', now()
  );
  if delayed_claim#>>'{data,unlocked}' <> 'true' then
    raise exception 'delayed in-window purchase was not reconciled: %', delayed_claim;
  end if;
end
$$;

-- Activity delivery leases only the exact current canonical snapshot, never
-- overlaps revisions for one subscription, and fails closed for former users.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status, score_revision
) values (
  '89000000-0000-4000-8000-000000000001',
  '89000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Activity Lease', '2026-08-13', '2026-08-13', 'live', 1
);
insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp
) values (
  '89100000-0000-4000-8000-000000000001',
  '89000000-0000-4000-8000-000000000001',
  '81000000-0000-4000-8000-000000000001',
  'Captain', 'captain', 'yes'
);
insert into public.trip_leaderboard_snapshots (
  trip_id, revision, scoring_engine_version, payload, computed_at
) values (
  '89000000-0000-4000-8000-000000000001', 1, 'tee-circle-ts-2',
  '{"schemaVersion":1,"tripId":"89000000-0000-4000-8000-000000000011","revision":1,"status":"live","primaryFormat":"stableford","currentRound":null,"boards":[],"moment":null,"generatedAt":"2026-08-13T12:00:00Z"}'::jsonb,
  '2026-08-13T12:00:00Z'
);
do $$
declare first_registration jsonb; replacement jsonb; first_lease jsonb;
  overlapping jsonb; completed jsonb; newer jsonb; retry_result jsonb;
  retried jsonb; final_result jsonb; cleaned jsonb; subscription_id uuid;
  first_timestamp bigint;
begin
  first_registration := public.register_live_activity_v1(
    '89000000-0000-4000-8000-000000000001', 'activity-lease-device',
    'activity-lease-a', repeat('d', 64), 'sandbox', null
  );
  replacement := public.register_live_activity_v1(
    '89000000-0000-4000-8000-000000000001', 'activity-lease-device',
    'activity-lease-b', repeat('e', 64), 'sandbox', null
  );
  if first_registration ? 'error' or replacement ? 'error'
     or (select count(*) from public.live_activity_subscriptions
         where user_id = '81000000-0000-4000-8000-000000000001'
           and device_id = 'activity-lease-device' and ended_at is null) <> 1 then
    raise exception 'one-active Activity registration failed: %, %', first_registration, replacement;
  end if;

  first_lease := public.lease_live_activity_deliveries_service_v1(
    '89000000-0000-4000-8000-000000000001', 1, 10
  );
  subscription_id := (first_lease#>>'{data,deliveries,0,subscriptionId}')::uuid;
  first_timestamp := (first_lease#>>'{data,deliveries,0,activityTimestamp}')::bigint;
  overlapping := public.lease_live_activity_deliveries_service_v1(
    '89000000-0000-4000-8000-000000000001', 1, 10
  );
  if first_lease#>>'{data,deliveries,0,revision}' <> '1'
     or first_lease#>>'{data,deliveries,0,viewerPlayerId}' <> '89100000-0000-4000-8000-000000000001'
     or jsonb_array_length(overlapping#>'{data,deliveries}') <> 0 then
    raise exception 'Activity revisions overlapped: %, %', first_lease, overlapping;
  end if;
  completed := public.complete_live_activity_delivery_service_v1(
    subscription_id, 1,
    (first_lease#>>'{data,deliveries,0,leaseId}')::uuid,
    'delivered', false
  );
  if completed#>>'{data,status}' <> 'delivered' then
    raise exception 'Activity lease completion failed: %', completed;
  end if;

  update public.trips set score_revision = 2
  where id = '89000000-0000-4000-8000-000000000001';
  insert into public.trip_leaderboard_snapshots (
    trip_id, revision, scoring_engine_version, payload, computed_at
  ) values (
    '89000000-0000-4000-8000-000000000001', 2, 'tee-circle-ts-2',
    '{"schemaVersion":1,"tripId":"89000000-0000-4000-8000-000000000011","revision":2,"status":"live","primaryFormat":"stableford","currentRound":null,"boards":[],"moment":null,"generatedAt":"2026-08-13T12:01:00Z"}'::jsonb,
    '2026-08-13T12:01:00Z'
  );
  newer := public.lease_live_activity_deliveries_service_v1(
    '89000000-0000-4000-8000-000000000001', 1, 10
  );
  if newer#>>'{data,deliveries,0,revision}' <> '2'
     or (newer#>>'{data,deliveries,0,activityTimestamp}')::bigint <= first_timestamp then
    raise exception 'historical direct dispatch did not advance to current snapshot: %', newer;
  end if;
  retry_result := public.complete_live_activity_delivery_service_v1(
    subscription_id, 2,
    (newer#>>'{data,deliveries,0,leaseId}')::uuid,
    'retry', false
  );
  retried := public.lease_live_activity_deliveries_service_v1(
    '89000000-0000-4000-8000-000000000001', 2, 10
  );
  final_result := public.complete_live_activity_delivery_service_v1(
    subscription_id, 2,
    (retried#>>'{data,deliveries,0,leaseId}')::uuid,
    'delivered', false
  );
  if retry_result#>>'{data,status}' <> 'retry'
     or retried#>>'{data,deliveries,0,revision}' <> '2'
     or final_result#>>'{data,status}' <> 'delivered'
     or (select last_delivered_revision from public.live_activity_subscriptions
         where id = subscription_id) <> 2 then
    raise exception 'retryable Activity delivery was lost: %, %, %', retry_result, retried, final_result;
  end if;

  update public.trip_players set claimed_user_id = null
  where id = '89100000-0000-4000-8000-000000000001';
  cleaned := public.lease_live_activity_deliveries_service_v1(null, null, 10);
  if (select ended_at from public.live_activity_subscriptions
      where id = subscription_id) is null then
    raise exception 'dispatcher retained a former trip member: %', cleaned;
  end if;
end
$$;

-- Latest-per-trip lookup cannot starve one trip behind another trip's history;
-- a supplied revision is an exact filter.
insert into public.trip_leaderboard_snapshots (
  trip_id, revision, scoring_engine_version, payload, computed_at
) values
  ('84000000-0000-4000-8000-000000000001', 1, 'test', '{"schemaVersion":1,"revision":1}'::jsonb, '2026-08-04T12:00:00Z'),
  ('84000000-0000-4000-8000-000000000001', 3, 'test', '{"schemaVersion":1,"revision":3}'::jsonb, '2026-08-05T12:00:00Z'),
  ('82000000-0000-4000-8000-000000000001', 0, 'test', '{"schemaVersion":1,"revision":0}'::jsonb, '2026-08-01T12:00:00Z');
do $$
declare latest_result jsonb; exact_result jsonb; lifecycle jsonb; session_trip jsonb;
begin
  latest_result := public.get_latest_activity_snapshots_service_v1(
    array[
      '84000000-0000-4000-8000-000000000001'::uuid,
      '82000000-0000-4000-8000-000000000001'::uuid
    ], null
  );
  select value into lifecycle
  from jsonb_array_elements(latest_result#>'{data,snapshots}') value
  where value->>'tripId' = '84000000-0000-4000-8000-000000000001';
  select value into session_trip
  from jsonb_array_elements(latest_result#>'{data,snapshots}') value
  where value->>'tripId' = '82000000-0000-4000-8000-000000000001';
  if jsonb_array_length(latest_result#>'{data,snapshots}') <> 2
     or lifecycle->>'revision' <> '3'
     or session_trip->>'revision' <> '0'
     or lifecycle->>'computedAt' is null then
    raise exception 'latest activity snapshots failed: %', latest_result;
  end if;
  exact_result := public.get_latest_activity_snapshots_service_v1(
    array[
      '84000000-0000-4000-8000-000000000001'::uuid,
      '82000000-0000-4000-8000-000000000001'::uuid
    ], 1
  );
  if jsonb_array_length(exact_result#>'{data,snapshots}') <> 1
     or exact_result#>>'{data,snapshots,0,revision}' <> '1' then
    raise exception 'exact activity snapshot revision filter failed: %', exact_result;
  end if;
end
$$;

-- Snapshot revisions are append-only. A second same-engine writer receives the
-- first stored canonical payload instead of overwriting generated content.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status, score_revision
) values (
  '87000000-0000-4000-8000-000000000001',
  '87000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Snapshot Integrity', '2026-08-08', '2026-08-08', 'live', 0
);
do $$
declare first_result jsonb; replay_result jsonb; old_engine_result jsonb;
begin
  first_result := public.persist_trip_snapshot_v1(
    '87000000-0000-4000-8000-000000000001', 0,
    '{"schemaVersion":1,"tripId":"87000000-0000-4000-8000-000000000011","revision":0,"marker":"first"}'::jsonb,
    'tee-circle-ts-2'
  );
  replay_result := public.persist_trip_snapshot_v1(
    '87000000-0000-4000-8000-000000000001', 0,
    '{"schemaVersion":1,"tripId":"87000000-0000-4000-8000-000000000011","revision":0,"marker":"second"}'::jsonb,
    'tee-circle-ts-2'
  );
  old_engine_result := public.persist_trip_snapshot_v1(
    '87000000-0000-4000-8000-000000000001', 0,
    '{"schemaVersion":1,"tripId":"87000000-0000-4000-8000-000000000011","revision":0,"marker":"old"}'::jsonb,
    'tee-circle-ts-1'
  );
  if first_result#>>'{data,idempotentReplay}' <> 'false'
     or replay_result#>>'{data,idempotentReplay}' <> 'true'
     or replay_result#>>'{data,payload,marker}' <> 'first'
     or old_engine_result#>>'{error,code}' <> 'unsupported_scoring_engine'
     or (select count(*) from public.trip_leaderboard_snapshots
         where trip_id = '87000000-0000-4000-8000-000000000001' and revision = 0) <> 1
     or (select payload->>'marker' from public.trip_leaderboard_snapshots
         where trip_id = '87000000-0000-4000-8000-000000000001' and revision = 0) <> 'first' then
    raise exception 'append-only snapshot persistence failed: %, %, %', first_result, replay_result, old_engine_result;
  end if;
end
$$;

-- The DB-only repair primitive restores a missing current-revision outbox row.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status
) values (
  '86000000-0000-4000-8000-000000000001',
  '86000000-0000-4000-8000-000000000011',
  '81000000-0000-4000-8000-000000000001',
  'Repair Integrity', '2026-08-07', '2026-08-07', 'ready'
);
delete from tee_internal.leaderboard_recompute_jobs
where trip_id = '86000000-0000-4000-8000-000000000001' and revision = 0;
do $$
declare result jsonb;
begin
  result := public.enqueue_missing_trip_snapshot_jobs_service_v1();
  if (result#>>'{data,enqueued}')::integer < 1
     or not exists (
       select 1 from tee_internal.leaderboard_recompute_jobs
       where trip_id = '86000000-0000-4000-8000-000000000001'
         and revision = 0 and status = 'pending'
     ) then
    raise exception 'missing snapshot repair job was not restored: %', result;
  end if;
end
$$;

-- Mutating entry points consistently fail closed while the server kill switch
-- is off. Cleanup/revoke commands intentionally remain available.
update tee_internal.runtime_flags set enabled = false
where key = 'native_writes_enabled';
do $$
declare
  accept_result jsonb;
  update_result jsonb;
  participation_result jsonb;
  session_result jsonb;
  push_result jsonb;
  activity_result jsonb;
  invite_result jsonb;
  purchase_result jsonb;
  transfer_result jsonb;
begin
  accept_result := public.accept_trip_invite_v1(
    'integrity_disabled_token_00000000000000000001', null
  );
  update_result := public.update_trip_player_v1(
    '84100000-0000-4000-8000-000000000002', '{"displayName":"Blocked"}'::jsonb
  );
  participation_result := public.set_round_participation_v1(
    '84200000-0000-4000-8000-000000000001',
    '84100000-0000-4000-8000-000000000002',
    0::smallint, 0::smallint, 'active'
  );
  session_result := public.issue_extension_session_v1(
    '82000000-0000-4000-8000-000000000001', 'integrity-device-002'
  );
  push_result := public.register_device_push_v1(
    'integrity-device-002', repeat('a', 64), 'sandbox', 'com.teecircle.app'
  );
  activity_result := public.register_live_activity_v1(
    '83000000-0000-4000-8000-000000000001', 'integrity-device-002',
    'activity-002', repeat('b', 64), 'sandbox', null
  );
  invite_result := public.create_trip_invite_v1(
    '84000000-0000-4000-8000-000000000001', now() + interval '1 day', null,
    '86500000-0000-4000-8000-000000000001'
  );
  purchase_result := public.create_trip_purchase_intent_v1(
    '85000000-0000-4000-8000-000000000001',
    '86500000-0000-4000-8000-000000000002'
  );
  transfer_result := public.transfer_trip_ownership_v1(
    '84000000-0000-4000-8000-000000000001',
    '84100000-0000-4000-8000-000000000002'
  );
  if accept_result#>>'{error,code}' <> 'native_writes_disabled'
     or update_result#>>'{error,code}' <> 'native_writes_disabled'
     or participation_result#>>'{error,code}' <> 'native_writes_disabled'
     or session_result#>>'{error,code}' <> 'native_writes_disabled'
     or push_result#>>'{error,code}' <> 'native_writes_disabled'
     or activity_result#>>'{error,code}' <> 'native_writes_disabled'
     or invite_result#>>'{error,code}' <> 'native_writes_disabled'
     or purchase_result#>>'{error,code}' <> 'native_writes_disabled'
     or transfer_result#>>'{error,code}' <> 'native_writes_disabled' then
    raise exception 'kill-switch guard is incomplete: %, %, %, %, %, %, %, %, %',
      accept_result, update_result, participation_result, session_result,
      push_result, activity_result, invite_result, purchase_result, transfer_result;
  end if;
end
$$;

rollback;
