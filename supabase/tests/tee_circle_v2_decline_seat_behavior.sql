-- decline_trip_seat_v1 regression: only the claimed player can decline, the
-- captain seat and archived trips are protected, and a decline releases the
-- claim, marks rsvp 'no', revokes extension sessions, and removes trip
-- membership. Run only against the disposable fixture through
-- run-local-v2.sh.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

insert into auth.users (id) values
  ('91000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002');

insert into public.profiles (id, full_name) values
  ('91000000-0000-4000-8000-000000000001', 'Decline Captain'),
  ('91000000-0000-4000-8000-000000000002', 'Decline Player');

insert into public.trips (id, public_id, owner_id, name, starts_on, ends_on, status) values
  ('92000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000011',
   '91000000-0000-4000-8000-000000000001', 'Decline Trip', '2026-08-01', '2026-08-02', 'ready'),
  ('92000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000012',
   '91000000-0000-4000-8000-000000000001', 'Archived Trip', '2026-05-01', '2026-05-02', 'archived');

insert into public.trip_players (id, trip_id, claimed_user_id, display_name, role, rsvp) values
  ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
   '91000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes'),
  ('93000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001',
   '91000000-0000-4000-8000-000000000002', 'Player', 'player', 'yes'),
  ('93000000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000002',
   '91000000-0000-4000-8000-000000000002', 'Archived Player', 'player', 'yes');

insert into public.extension_sessions (
  id, trip_id, user_id, trip_player_id, device_id, token_hash, expires_at
) values (
  '94000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002', '93000000-0000-4000-8000-000000000002',
  'decline-device-1', '\x11'::bytea, now() + interval '1 hour'
);

-- An anonymous caller is rejected before touching any row.
select set_config('request.jwt.claim.sub', '', true);
do $$
declare result jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  if result#>>'{error,code}' <> 'unauthenticated' then
    raise exception 'anonymous decline was not rejected: %', result;
  end if;
end
$$;

-- Someone else's seat (even for the captain) is forbidden: decline is a
-- first-person action; captains keep release_trip_player_claim_v1.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
do $$
declare result jsonb; captain_result jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  captain_result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000001');
  if result#>>'{error,code}' <> 'forbidden'
     or captain_result#>>'{error,code}' <> 'captain_claim_required' then
    raise exception 'decline authorization guards failed: %, %', result, captain_result;
  end if;
end
$$;

-- Archived trips cannot change roster claims.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare result jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000003');
  if result#>>'{error,code}' <> 'trip_archived' then
    raise exception 'archived decline guard failed: %', result;
  end if;
end
$$;

-- A roster id that doesn't exist fails closed before any authorization check
-- has a row to reason about.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare result jsonb;
begin
  result := public.decline_trip_seat_v1('93999999-0000-4000-8000-000000000099');
  if result#>>'{error,code}' <> 'player_not_found' then
    raise exception 'missing seat decline guard failed: %', result;
  end if;
end
$$;

-- While the server kill switch is off, decline fails closed and mutates
-- nothing on the seat it would otherwise have released.
update tee_internal.runtime_flags set enabled = false
where key = 'native_writes_enabled';
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare
  result jsonb;
  before_claimed uuid;
  before_rsvp text;
  after_claimed uuid;
  after_rsvp text;
begin
  select claimed_user_id, rsvp into before_claimed, before_rsvp
  from public.trip_players where id = '93000000-0000-4000-8000-000000000002';

  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  if result#>>'{error,code}' <> 'native_writes_disabled'
     or result#>>'{error,retryable}' <> 'true' then
    raise exception 'kill-switch decline guard failed: %', result;
  end if;

  select claimed_user_id, rsvp into after_claimed, after_rsvp
  from public.trip_players where id = '93000000-0000-4000-8000-000000000002';
  if after_claimed is distinct from before_claimed or after_rsvp is distinct from before_rsvp then
    raise exception 'decline mutated the seat while native writes were disabled: %, %',
      after_claimed, after_rsvp;
  end if;
end
$$;
update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

-- The claimed player declines: claim released, rsvp 'no', sessions revoked,
-- membership gone. A repeat decline finds no claim and is forbidden.
do $$
declare result jsonb; replay jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  if result#>>'{data,claimed}' <> 'false' or result#>>'{data,rsvp}' <> 'no' then
    raise exception 'decline did not succeed: %', result;
  end if;
  if (select claimed_user_id from public.trip_players where id = '93000000-0000-4000-8000-000000000002') is not null
     or (select rsvp from public.trip_players where id = '93000000-0000-4000-8000-000000000002') <> 'no'
     or (select display_name from public.trip_players where id = '93000000-0000-4000-8000-000000000002') <> 'Player' then
    raise exception 'decline row state is wrong';
  end if;
  if exists (
    select 1 from public.extension_sessions
    where trip_player_id = '93000000-0000-4000-8000-000000000002' and revoked_at is null
  ) then
    raise exception 'decline left an active extension session';
  end if;
  if tee_internal.is_trip_member(
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'declined player is still a trip member';
  end if;
  replay := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  if replay#>>'{error,code}' <> 'forbidden' then
    raise exception 'repeat decline should be forbidden once the claim is gone: %', replay;
  end if;
end
$$;

rollback;
