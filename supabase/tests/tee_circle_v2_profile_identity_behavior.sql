-- Profile identity commands for the native client. Run only after
-- verified_legacy_schema.sql and every ordered v2 migration.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

insert into auth.users (id) values
  ('c1000000-0000-4000-8000-000000000001'),
  ('c1000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000003');

-- Two seeded Expo-era profiles; the third user has no row at all, which is the
-- state every native-only signup starts in because nothing seeds public.profiles.
insert into public.profiles (id, full_name, username) values
  ('c1000000-0000-4000-8000-000000000001', 'Existing Golfer', 'existing-golfer'),
  ('c1000000-0000-4000-8000-000000000002', 'Taken Handle', 'taken-handle');

do $$
declare
  v_response jsonb;
begin
  -- An anonymous caller is rejected before touching any row.
  perform set_config('request.jwt.claim.sub', '', true);
  v_response := public.get_my_profile_v1();
  if v_response->'error'->>'code' is distinct from 'unauthenticated' then
    raise exception 'anonymous profile read was not rejected: %', v_response;
  end if;

  v_response := public.update_my_profile_v1('Anon', 'anon-user');
  if v_response->'error'->>'code' is distinct from 'unauthenticated' then
    raise exception 'anonymous profile write was not rejected: %', v_response;
  end if;

  -- An Expo-era profile reads back through the native command unchanged.
  perform set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000001', true);
  v_response := public.get_my_profile_v1();
  if v_response->'data'->>'fullName' is distinct from 'Existing Golfer'
     or v_response->'data'->>'username' is distinct from 'existing-golfer' then
    raise exception 'legacy profile did not survive the native read: %', v_response;
  end if;

  -- Handles normalize the same way src/utils/username.ts does.
  v_response := public.update_my_profile_v1('  Existing Golfer  ', '  @Existing_Golfer  ');
  if v_response->'data'->>'username' is distinct from 'existing_golfer' then
    raise exception 'username was not normalized: %', v_response;
  end if;
  if v_response->'data'->>'fullName' is distinct from 'Existing Golfer' then
    raise exception 'full name was not trimmed: %', v_response;
  end if;

  -- Case-insensitive collision against another account is refused rather than
  -- surfacing as a raw unique violation.
  v_response := public.update_my_profile_v1('Existing Golfer', 'TAKEN-HANDLE');
  if v_response->'error'->>'code' is distinct from 'username_taken' then
    raise exception 'case-insensitive collision was allowed: %', v_response;
  end if;

  -- Reclaiming your own handle is not a collision.
  v_response := public.update_my_profile_v1('Existing Golfer', 'existing_golfer');
  if v_response->'data'->>'username' is distinct from 'existing_golfer' then
    raise exception 'self-reclaim was treated as taken: %', v_response;
  end if;

  -- Shape rules.
  v_response := public.update_my_profile_v1('Existing Golfer', 'ab');
  if v_response->'error'->>'code' is distinct from 'invalid_username' then
    raise exception 'short username was accepted: %', v_response;
  end if;
  v_response := public.update_my_profile_v1('Existing Golfer', 'has spaces');
  if v_response->'error'->>'code' is distinct from 'invalid_username' then
    raise exception 'username with a space was accepted: %', v_response;
  end if;
  v_response := public.update_my_profile_v1('Existing Golfer', repeat('a', 21));
  if v_response->'error'->>'code' is distinct from 'invalid_username' then
    raise exception 'overlong username was accepted: %', v_response;
  end if;
  v_response := public.update_my_profile_v1('   ', 'existing_golfer');
  if v_response->'error'->>'code' is distinct from 'invalid_request' then
    raise exception 'blank name was accepted: %', v_response;
  end if;

  -- A native-only account has no profiles row; the command must create one
  -- rather than silently updating nothing. full_name is NOT NULL here.
  perform set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000003', true);
  v_response := public.get_my_profile_v1();
  if v_response->'data'->>'fullName' is not null
     or v_response->'data'->>'username' is not null then
    raise exception 'absent profile did not read back as unset: %', v_response;
  end if;

  v_response := public.update_my_profile_v1('Native Newcomer', 'native-newcomer');
  if v_response->'data'->>'username' is distinct from 'native-newcomer' then
    raise exception 'native signup could not create a profile: %', v_response;
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = 'c1000000-0000-4000-8000-000000000003'
      and p.full_name = 'Native Newcomer'
      and p.username = 'native-newcomer'
  ) then
    raise exception 'profile row was not persisted for a native signup';
  end if;

  -- A brand-new account cannot squat an existing handle either.
  v_response := public.update_my_profile_v1('Native Newcomer', 'Existing_Golfer');
  if v_response->'error'->>'code' is distinct from 'username_taken' then
    raise exception 'insert path allowed a taken handle: %', v_response;
  end if;
end
$$;

-- The write command respects the native kill switch; the read does not, so a
-- paused rollout still renders the signed-in identity.
update tee_internal.runtime_flags set enabled = false
where key = 'native_writes_enabled';

do $$
declare
  v_response jsonb;
begin
  perform set_config('request.jwt.claim.sub', 'c1000000-0000-4000-8000-000000000001', true);
  v_response := public.update_my_profile_v1('Existing Golfer', 'existing_golfer');
  if v_response->'error'->>'code' is distinct from 'native_writes_disabled' then
    raise exception 'profile write ignored the native kill switch: %', v_response;
  end if;

  v_response := public.get_my_profile_v1();
  if v_response->'data'->>'username' is distinct from 'existing_golfer' then
    raise exception 'profile read was blocked by the native kill switch: %', v_response;
  end if;
end
$$;

rollback;
