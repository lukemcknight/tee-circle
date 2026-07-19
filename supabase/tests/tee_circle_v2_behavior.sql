-- Focused multi-user behavior regression. Run only against a disposable local
-- database after the verified legacy baseline and all v2 migrations.

begin;

update tee_internal.runtime_flags set enabled = true
where key in ('native_writes_enabled', 'public_previews_enabled');
update tee_internal.runtime_flags set enabled = false
where key = 'purchases_required';

insert into auth.users (id) values
  ('91000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002'),
  ('91000000-0000-4000-8000-000000000003'),
  ('91000000-0000-4000-8000-000000000004'),
  ('91000000-0000-4000-8000-000000000005');

insert into public.profiles (id, full_name) values
  ('91000000-0000-4000-8000-000000000001', 'Captain'),
  ('91000000-0000-4000-8000-000000000002', 'Player'),
  ('91000000-0000-4000-8000-000000000003', 'Scorer'),
  ('91000000-0000-4000-8000-000000000004', 'Bystander'),
  ('91000000-0000-4000-8000-000000000005', 'Second claimant');

-- Course-card reads return only the caller's reusable, unarchived cards and
-- always order their holes by hole number.
insert into public.course_cards (
  id, owner_id, name, course_name, hole_count, archived_at, updated_at
) values
  ('91500000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'Home tees', 'Captain Club', 9, null, '2026-07-13T12:00:00Z'),
  ('91500000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', 'Old card', 'Archived Club', 9, '2026-07-13T13:00:00Z', '2026-07-13T13:00:00Z'),
  ('91500000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000002', 'Private card', 'Player Club', 9, null, '2026-07-13T14:00:00Z');

insert into public.course_card_holes (course_card_id, hole_number, par, stroke_index, yards)
select card_id, hole, 4, hole, 300 + hole
from (
  values
    ('91500000-0000-4000-8000-000000000001'::uuid),
    ('91500000-0000-4000-8000-000000000002'::uuid),
    ('91500000-0000-4000-8000-000000000003'::uuid)
) cards(card_id)
cross join generate_series(1, 9) hole;

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
do $$
declare result jsonb; card jsonb;
begin
  result := public.get_course_cards_v1();
  if jsonb_array_length(result#>'{data,courseCards}') <> 1 then
    raise exception 'course-card read leaked or included archived cards: %', result;
  end if;
  card := result#>'{data,courseCards,0}';
  if card->>'id' <> '91500000-0000-4000-8000-000000000001'
     or card->>'courseName' <> 'Captain Club'
     or jsonb_array_length(card->'holes') <> 9
     or card#>>'{holes,0,holeNumber}' <> '1'
     or card#>>'{holes,8,holeNumber}' <> '9'
     or card ? 'ownerId'
     or card ? 'archivedAt' then
    raise exception 'course-card payload contract failed: %', result;
  end if;
end
$$;

insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on, status,
  enabled_formats, primary_format, scoring_mode, score_revision
) values (
  '92000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000002',
  '91000000-0000-4000-8000-000000000001',
  'Behavior Trip', '2026-07-13', '2026-07-13', 'live',
  array['stableford', 'skins'], 'stableford', 'gross', 0
);

insert into public.trip_players (
  id, trip_id, claimed_user_id, display_name, role, rsvp, handicap_snapshot
) values
  ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes', 8),
  ('93000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001', null, 'Player', 'player', 'pending', 12),
  ('93000000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000003', 'Scorer', 'scorer', 'yes', 5),
  ('93000000-0000-4000-8000-000000000004', '92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000004', 'Bystander', 'player', 'yes', 15);

insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, created_by,
  trip_id, trip_order, public_id, trip_round_status
) values (
  '94000000-0000-4000-8000-000000000001', 'Behavior Club',
  '2026-07-13T12:00:00-04:00', 9, 'ride',
  '91000000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001', 1,
  '94000000-0000-4000-8000-000000000002', 'live'
);

insert into public.round_holes (round_id, hole_number, par, stroke_index)
select '94000000-0000-4000-8000-000000000001', hole, 4, hole
from generate_series(1, 9) hole;

insert into public.trip_round_players (
  round_id, trip_player_id, course_handicap, playing_handicap, status
)
select '94000000-0000-4000-8000-000000000001', id,
  round(handicap_snapshot)::smallint, round(handicap_snapshot)::smallint, 'active'
from public.trip_players where trip_id = '92000000-0000-4000-8000-000000000001';

insert into public.trip_invites (
  id, trip_id, token_hash, created_by, expires_at
) values (
  '94500000-0000-4000-8000-000000000001',
  '92000000-0000-4000-8000-000000000001',
  extensions.digest(convert_to('behavior_claim_token_0000000000000000000001', 'UTF8'), 'sha256'),
  '91000000-0000-4000-8000-000000000001',
  now() + interval '1 day'
);

-- Authenticated table reads retain the safe roster fields, but account IDs
-- stay behind the bootstrap DTO. RLS authorization is evaluated only for the
-- JWT user: clients cannot call the internal helpers with another user ID.
set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000004', true);
do $$
declare
  v_roster_count integer;
  v_bootstrap jsonb;
begin
  select count(*) into v_roster_count
  from public.trip_players tp
  where tp.trip_id = '92000000-0000-4000-8000-000000000001';
  if v_roster_count <> 4 then
    raise exception 'safe roster columns or member RLS are unavailable: %', v_roster_count;
  end if;

  if not tee_internal.current_user_is_trip_member(
       '92000000-0000-4000-8000-000000000001'
     )
     or tee_internal.current_user_trip_role(
       '92000000-0000-4000-8000-000000000001'
     ) <> 'player'
     or tee_internal.current_user_can_manage_trip(
       '92000000-0000-4000-8000-000000000001'
     )
     or not tee_internal.current_user_can_score_player(
       '92000000-0000-4000-8000-000000000001',
       '93000000-0000-4000-8000-000000000004'
     ) then
    raise exception 'auth-bound roster helpers did not evaluate the JWT member';
  end if;

  begin
    perform tp.claimed_user_id
    from public.trip_players tp
    where tp.trip_id = '92000000-0000-4000-8000-000000000001';
    raise exception 'raw claimed_user_id unexpectedly readable';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform tee_internal.is_trip_member(
      '92000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001'
    );
    raise exception 'authenticated caller spoofed is_trip_member user id';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform tee_internal.trip_role(
      '92000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001'
    );
    raise exception 'authenticated caller spoofed trip_role user id';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform tee_internal.can_manage_trip(
      '92000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001'
    );
    raise exception 'authenticated caller spoofed can_manage_trip user id';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform tee_internal.can_score_player(
      '92000000-0000-4000-8000-000000000001',
      '93000000-0000-4000-8000-000000000001',
      '91000000-0000-4000-8000-000000000001'
    );
    raise exception 'authenticated caller spoofed can_score_player user id';
  exception when insufficient_privilege then
    null;
  end;

  v_bootstrap := public.get_trip_bootstrap_v1(
    '92000000-0000-4000-8000-000000000001'
  );
  if v_bootstrap ? 'error'
     or jsonb_array_length(v_bootstrap#>'{data,roster}') <> 4
     or not exists (
       select 1
       from jsonb_array_elements(v_bootstrap#>'{data,roster}') seat
       where seat->>'tripPlayerId' = '93000000-0000-4000-8000-000000000004'
         and seat->>'claimed' = 'true'
         and seat->>'isCurrentUser' = 'true'
     )
     or exists (
       select 1
       from jsonb_array_elements(v_bootstrap#>'{data,roster}') seat
       where seat ? 'claimedUserId' or seat ? 'claimed_user_id'
     ) then
    raise exception 'sanitized roster bootstrap contract failed: %', v_bootstrap;
  end if;

  -- Trip player 2's seat is still unclaimed here (claimed_user_id is null;
  -- the invite claim below has not run yet). Every roster entry's
  -- isCurrentUser must still be a JSON boolean, never SQL NULL, or the iOS
  -- client's non-optional Bool decode fails.
  if exists (
       select 1
       from jsonb_array_elements(v_bootstrap#>'{data,roster}') seat
       where jsonb_typeof(seat->'isCurrentUser') <> 'boolean'
     ) then
    raise exception 'roster isCurrentUser was not a JSON boolean for every seat (unclaimed seat leaked SQL null): %', v_bootstrap;
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '91000000-0000-4000-8000-000000000005',
    true
  );
  if tee_internal.current_user_is_trip_member(
    '92000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'auth-bound wrapper reused another member identity';
  end if;
end
$$;
reset role;

-- Invite claim race: the first claimant wins and a second non-member sees a
-- stable seat error. Direct claim_trip_player_v1 is not a client capability.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare result jsonb;
begin
  result := public.accept_trip_invite_v1(
    'behavior_claim_token_0000000000000000000001',
    '93000000-0000-4000-8000-000000000002'
  );
  if result#>>'{data,accepted}' <> 'true' then raise exception 'first invite claim failed: %', result; end if;
end
$$;
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000005', true);
do $$
declare result jsonb;
begin
  result := public.accept_trip_invite_v1(
    'behavior_claim_token_0000000000000000000001',
    '93000000-0000-4000-8000-000000000002'
  );
  if result#>>'{error,code}' <> 'seat_already_claimed' then raise exception 'claim race was not rejected: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000004', true);

-- A plain player cannot score another seat. Self scoring is idempotent, and a
-- scorer may edit anyone using the latest global trip revision.
do $$
declare result jsonb;
begin
  result := public.record_hole_score_v1(
    '94000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002',
    1::smallint, 5::smallint, 0::smallint,
    '95000000-0000-4000-8000-000000000001', 0
  );
  if result#>>'{error,code}' <> 'forbidden' then raise exception 'plain player scored another seat: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare first_result jsonb; replay_result jsonb; reused_result jsonb;
begin
  first_result := public.record_hole_score_v1(
    '94000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002',
    1::smallint, 5::smallint, 0::smallint,
    '95000000-0000-4000-8000-000000000002', 0
  );
  replay_result := public.record_hole_score_v1(
    '94000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002',
    1::smallint, 5::smallint, 0::smallint,
    '95000000-0000-4000-8000-000000000002', 0
  );
  reused_result := public.record_hole_score_v1(
    '94000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002',
    1::smallint, 6::smallint, 0::smallint,
    '95000000-0000-4000-8000-000000000002', 1
  );
  if first_result#>>'{data,acceptedRevision}' <> '1' then raise exception 'self score failed: %', first_result; end if;
  if replay_result#>>'{data,idempotentReplay}' <> 'true' then raise exception 'score replay was not idempotent: %', replay_result; end if;
  if reused_result#>>'{error,code}' <> 'idempotency_key_reused' then raise exception 'changed replay was accepted: %', reused_result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000003', true);
do $$
declare result jsonb;
begin
  result := public.record_hole_score_v1(
    '94000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002',
    1::smallint, 4::smallint, 0::smallint,
    '95000000-0000-4000-8000-000000000003', 1
  );
  if result#>>'{data,acceptedRevision}' <> '2' then raise exception 'scorer authority failed: %', result; end if;
end
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare result jsonb;
begin
  result := public.record_hole_score_v1(
    '94000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002',
    2::smallint, 4::smallint, 0::smallint,
    '95000000-0000-4000-8000-000000000004', 1
  );
  if result#>>'{error,code}' <> 'score_conflict'
     or result#>>'{error,currentRevision}' <> '2'
     or result#>>'{error,details,currentScore}' is not null
     or not (result#>'{error,details}' ? 'currentScore') then
    raise exception 'stale global revision was accepted: %', result;
  end if;
end
$$;

-- Seed the canonical current snapshot, then assert public preview contains no
-- auth user IDs and revocation produces an explicit terminal state.
insert into public.trip_leaderboard_snapshots (
  trip_id, revision, scoring_engine_version, payload
) values (
  '92000000-0000-4000-8000-000000000001', 2, 'test-1',
  '{"schemaVersion":1,"tripId":"92000000-0000-4000-8000-000000000002","revision":2,"status":"live","primaryFormat":"stableford","currentRound":{"publicId":"94000000-0000-4000-8000-000000000002","name":"Behavior Club","throughHole":0},"boards":[{"format":"stableford","scoring":"gross","standings":[]}],"moment":{"kind":"score_update","summary":"Standings updated"},"generatedAt":"2026-07-13T22:00:00Z"}'::jsonb
);

-- A pilot with purchases disabled is effectively unlocked on every native
-- surface, while enabling the production gate makes the same unentitled trip
-- report locked. Neither DTO exposes the purchase evidence used internally.
do $$
declare
  session_result jsonb;
  bootstrap jsonb;
  messages_bootstrap jsonb;
  token_hash text;
begin
  session_result := public.issue_extension_session_v1(
    '92000000-0000-4000-8000-000000000001',
    'behavior-pilot-device'
  );
  if session_result ? 'error' then
    raise exception 'pilot extension session failed: %', session_result;
  end if;
  token_hash := encode(
    extensions.digest(
      convert_to(session_result#>>'{data,sessionToken}', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  bootstrap := public.get_trip_bootstrap_v1(
    '92000000-0000-4000-8000-000000000001'
  );
  messages_bootstrap := public.get_messages_bootstrap_service_v1(token_hash);
  if bootstrap#>>'{data,trip,isUnlocked}' <> 'true'
     or messages_bootstrap#>>'{data,trip,isEntitled}' <> 'true' then
    raise exception 'pilot unlock state diverged across DTOs: %, %',
      bootstrap, messages_bootstrap;
  end if;
  if (bootstrap#>'{data,trip}') ?| array[
       'purchaseIntentId', 'transactionId', 'revenuecatTransactionId',
       'environment', 'productId'
     ]
     or (messages_bootstrap#>'{data,trip}') ?| array[
       'purchaseIntentId', 'transactionId', 'revenuecatTransactionId',
       'environment', 'productId'
     ] then
    raise exception 'sanitized unlock DTO leaked purchase evidence: %, %',
      bootstrap, messages_bootstrap;
  end if;

  update tee_internal.runtime_flags set enabled = true
  where key = 'purchases_required';
  bootstrap := public.get_trip_bootstrap_v1(
    '92000000-0000-4000-8000-000000000001'
  );
  messages_bootstrap := public.get_messages_bootstrap_service_v1(token_hash);
  if bootstrap#>>'{data,trip,isUnlocked}' <> 'false'
     or messages_bootstrap#>>'{data,trip,isEntitled}' <> 'false' then
    raise exception 'production purchase gate did not fail closed: %, %',
      bootstrap, messages_bootstrap;
  end if;

  update tee_internal.runtime_flags set enabled = false
  where key = 'purchases_required';
end
$$;

create temporary table v2_behavior_state (key text primary key, value text not null);
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
do $$
declare result jsonb; token text;
begin
  result := public.create_trip_invite_v1(
    '92000000-0000-4000-8000-000000000001', now() + interval '1 day', null,
    '95000000-0000-4000-8000-000000000005'
  );
  token := result#>>'{data,inviteToken}';
  if token is null then raise exception 'invite creation failed: %', result; end if;
  insert into v2_behavior_state values ('invite_token', token), ('invite_id', result#>>'{data,inviteId}');
end
$$;

do $$
declare preview jsonb; token text;
begin
  select value into token from v2_behavior_state where key = 'invite_token';
  preview := public.resolve_public_trip_preview_service_v1(
    encode(extensions.digest(convert_to(token, 'UTF8'), 'sha256'), 'hex')
  );
  if preview is null or preview ? 'errorCode' then raise exception 'public preview failed: %', preview; end if;
  if preview::text like '%91000000-0000-4000-8000-%'
     or preview::text like '%claimedUserId%'
     or preview::text like '%handicap%' then
    raise exception 'public preview leaked private roster data: %', preview;
  end if;
end
$$;

do $$
declare result jsonb; preview jsonb; token text; invite_id uuid;
begin
  select value into token from v2_behavior_state where key = 'invite_token';
  select value::uuid into invite_id from v2_behavior_state where key = 'invite_id';
  result := public.revoke_trip_invite_v1(invite_id);
  preview := public.resolve_public_trip_preview_service_v1(
    encode(extensions.digest(convert_to(token, 'UTF8'), 'sha256'), 'hex')
  );
  if result#>>'{data,revoked}' <> 'true' or preview->>'errorCode' <> 'invite_revoked' then
    raise exception 'invite revocation failed: %, %', result, preview;
  end if;
end
$$;

-- Legacy rounds allow a null creator (pre-account or orphaned production
-- rows; public.rounds.created_by is nullable). A caller who only responded
-- to the round (not created it) must still see JSON booleans for
-- isCreator/canConvert, never SQL NULL from a direct `= v_user_id` compare.
insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, created_by
) values (
  '94900000-0000-4000-8000-000000000001', 'Orphaned Legacy Club',
  '2026-07-20T09:00:00-04:00', 9, 'walk', null
);
insert into public.round_responses (round_id, user_id, response) values (
  '94900000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000004',
  'yes'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000004', true);
do $$
declare
  v_rounds jsonb;
  v_round jsonb;
begin
  v_rounds := public.get_legacy_rounds_v1();
  if v_rounds ? 'error' then
    raise exception 'legacy rounds read failed: %', v_rounds;
  end if;
  select seat into v_round
  from jsonb_array_elements(v_rounds#>'{data,rounds}') seat
  where seat->>'roundId' = '94900000-0000-4000-8000-000000000001';
  if v_round is null then
    raise exception 'orphaned legacy round missing from responder view: %', v_rounds;
  end if;
  if jsonb_typeof(v_round->'isCreator') <> 'boolean'
     or jsonb_typeof(v_round->'canConvert') <> 'boolean' then
    raise exception 'legacy round isCreator/canConvert was not a JSON boolean for a null creator: %', v_round;
  end if;
  if v_round->>'isCreator' <> 'false' or v_round->>'canConvert' <> 'false' then
    raise exception 'non-creator responder incorrectly saw isCreator/canConvert true: %', v_round;
  end if;
end
$$;
reset role;
-- request.jwt.claim.sub is transaction-local (set_config ... true) and
-- outlives the role reset above; restore the trip owner identity the
-- following blocks expect.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);

-- Ownership blocks account deletion until transfer. The database FK remains a
-- final defense even if an old deletion path skips the blocker command.
do $$
begin
  begin
    delete from auth.users where id = '91000000-0000-4000-8000-000000000001';
    raise exception 'trip owner deletion unexpectedly succeeded';
  exception when foreign_key_violation then
    null;
  end;
end
$$;

do $$
declare blockers jsonb; transfer_result jsonb;
begin
  blockers := public.get_account_deletion_blockers_v1();
  if blockers#>>'{data,canDelete}' <> 'false' then raise exception 'ownership blocker missing: %', blockers; end if;
  transfer_result := public.transfer_trip_ownership_v1(
    '92000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002'
  );
  if transfer_result ? 'error' then raise exception 'ownership transfer failed: %', transfer_result; end if;
  blockers := public.get_account_deletion_blockers_v1();
  if blockers#>>'{data,canDelete}' <> 'true' then raise exception 'old owner remains blocked: %', blockers; end if;
end
$$;

-- A verified App Store transaction may unlock exactly one trip.
insert into public.trips (
  id, public_id, owner_id, name, starts_on, ends_on
) values
  ('96000000-0000-4000-8000-000000000001', '96000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', 'Purchase One', '2026-08-01', '2026-08-01'),
  ('96000000-0000-4000-8000-000000000003', '96000000-0000-4000-8000-000000000004', '91000000-0000-4000-8000-000000000001', 'Purchase Two', '2026-08-02', '2026-08-02');

do $$
declare first_intent jsonb; second_intent jsonb; first_verify jsonb; replay_verify jsonb;
begin
  first_intent := public.create_trip_purchase_intent_v1(
    '96000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000006'
  );
  first_verify := public.verify_trip_purchase_v1(
    (first_intent#>>'{data,purchaseIntentId}')::uuid,
    'com.teecircle.app.trip_unlock_2999', 'transaction-replay-test',
    'production', now(), now()
  );
  second_intent := public.create_trip_purchase_intent_v1(
    '96000000-0000-4000-8000-000000000003', '95000000-0000-4000-8000-000000000007'
  );
  replay_verify := public.verify_trip_purchase_v1(
    (second_intent#>>'{data,purchaseIntentId}')::uuid,
    'com.teecircle.app.trip_unlock_2999', 'transaction-replay-test',
    'production', now(), now()
  );
  if first_verify#>>'{data,unlocked}' <> 'true' then raise exception 'first transaction verify failed: %', first_verify; end if;
  if replay_verify#>>'{error,code}' <> 'transaction_already_claimed' then
    raise exception 'transaction replay was accepted: %', replay_verify;
  end if;
end
$$;

rollback;
