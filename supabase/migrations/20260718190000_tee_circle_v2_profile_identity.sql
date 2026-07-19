set lock_timeout = '10s';
set statement_timeout = '5min';

-- Profile identity for the native client.
--
-- TeeCircle 2.0 shipped without any way to set a display name: the Swift client
-- guessed one from the email local part and never read or wrote public.profiles.
-- That guess then overrode create_trip_v1's existing profiles.full_name fallback,
-- so even v1 users who already had a name saw a mangled one.
--
-- These two commands give the native client the same identity surface the Expo
-- client had, without touching the legacy columns' shape. Nothing here creates,
-- drops, or alters a table; the Expo app keeps writing profiles.username directly
-- and both clients stay compatible.

create or replace function tee_internal.normalize_username(p_username text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  -- Mirrors normalizeUsername in src/utils/username.ts so a handle claimed in
  -- one client resolves identically in the other.
  select nullif(lower(btrim(regexp_replace(btrim(p_username), '^@+', ''))), '');
$$;

revoke all on function tee_internal.normalize_username(text) from public, anon, authenticated, service_role;

create or replace function public.get_my_profile_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;

  select * into v_profile from public.profiles p where p.id = v_user_id;

  -- A missing row is a valid state, not an error: the client treats null name and
  -- username as "this account still needs setup".
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'userId', v_user_id,
    'fullName', nullif(btrim(coalesce(v_profile.full_name, '')), ''),
    'username', nullif(btrim(coalesce(v_profile.username, '')), '')
  ));
end;
$$;

create or replace function public.update_my_profile_v1(p_full_name text, p_username text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_full_name text := nullif(btrim(coalesce(p_full_name, '')), '');
  v_username text := tee_internal.normalize_username(p_username);
  v_updated integer;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Profile changes are temporarily unavailable.', true);
  end if;

  if v_full_name is null or char_length(v_full_name) > 80 then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Enter a name of 80 characters or fewer.');
  end if;
  -- Same rule as USERNAME_REGEX in src/utils/username.ts.
  if v_username is null or v_username !~ '^[a-z0-9_-]{3,20}$' then
    return tee_internal.api_error(
      v_request_id,
      'invalid_username',
      'Usernames are 3-20 characters using letters, numbers, underscores, or hyphens.'
    );
  end if;

  -- Matched as lower(username) rather than through normalize_username so this
  -- check both uses the legacy profiles_username_lower_key index and agrees
  -- exactly with the constraint that would otherwise fire.
  if exists (
    select 1
    from public.profiles p
    where p.id <> v_user_id
      and lower(p.username) = v_username
  ) then
    return tee_internal.api_error(v_request_id, 'username_taken', 'That username is taken. Try another.');
  end if;

  update public.profiles p
     set full_name = v_full_name,
         username = v_username
   where p.id = v_user_id;
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    -- No trigger seeds public.profiles, so a native-only account has no row at
    -- all until this point. full_name is NOT NULL in the legacy schema, which is
    -- why the name is validated as present above.
    begin
      insert into public.profiles (id, full_name, username)
      values (v_user_id, v_full_name, v_username);
    exception
      when unique_violation then
        return tee_internal.api_error(v_request_id, 'username_taken', 'That username is taken. Try another.');
      when others then
        return tee_internal.api_error(
          v_request_id,
          'profile_unavailable',
          'Could not create your profile. Please contact support.',
          true
        );
    end;
  end if;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'userId', v_user_id,
    'fullName', v_full_name,
    'username', v_username
  ));
exception
  when unique_violation then
    -- Backstop for the legacy unique constraint racing between the check above
    -- and the write.
    return tee_internal.api_error(v_request_id, 'username_taken', 'That username is taken. Try another.');
end;
$$;

-- Match the ACL posture established in the function hardening migration: revoke
-- the implicit hosted grants, then restore only the signed-in entry points.
revoke all on function public.get_my_profile_v1() from public, anon, authenticated, service_role;
revoke all on function public.update_my_profile_v1(text, text) from public, anon, authenticated, service_role;

grant execute on function public.get_my_profile_v1() to authenticated;
grant execute on function public.update_my_profile_v1(text, text) to authenticated;
