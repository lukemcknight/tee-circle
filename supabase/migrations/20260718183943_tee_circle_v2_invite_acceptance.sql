set lock_timeout = '10s';
set statement_timeout = '5min';

-- Authenticated invitation acceptance. Anonymous preview remains read-only;
-- this command turns a valid bearer invitation into a claimed roster seat.


create or replace function public.accept_trip_invite_v1(
  p_invite_token text,
  p_trip_player_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_invite public.trip_invites%rowtype;
  v_trip public.trips%rowtype;
  v_player public.trip_players%rowtype;
  v_bootstrap jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if char_length(coalesce(p_invite_token, '')) not between 40 and 128
     or p_invite_token !~ '^[A-Za-z0-9_-]+$' then
    return tee_internal.api_error(v_request_id, 'invite_unavailable', 'This trip invitation is unavailable.');
  end if;
  select * into v_invite from public.trip_invites i
  where i.token_hash = extensions.digest(convert_to(p_invite_token, 'UTF8'), 'sha256')
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'invite_unavailable', 'This trip invitation is unavailable.');
  end if;
  if v_invite.revoked_at is not null then
    return tee_internal.api_error(v_request_id, 'invite_revoked', 'This trip invitation was revoked.');
  end if;
  if v_invite.expires_at is not null and v_invite.expires_at <= now() then
    return tee_internal.api_error(v_request_id, 'invite_expired', 'This trip invitation expired.');
  end if;
  select * into v_trip from public.trips t where t.id = v_invite.trip_id;
  if not found or v_trip.status not in ('ready', 'live', 'completed') then
    return tee_internal.api_error(v_request_id, 'invite_unavailable', 'This trip invitation is unavailable.');
  end if;

  if tee_internal.is_trip_member(v_trip.id, v_user_id) then
    v_bootstrap := public.get_trip_bootstrap_v1(v_trip.id)->'data';
    return tee_internal.api_success(v_request_id, jsonb_build_object(
      'accepted', true,
      'tripId', v_trip.id,
      'tripPlayerId', (
        select tp.id from public.trip_players tp
        where tp.trip_id = v_trip.id and tp.claimed_user_id = v_user_id limit 1
      ),
      'bootstrap', v_bootstrap
    ));
  end if;

  if p_trip_player_id is null then
    return tee_internal.api_success(v_request_id, jsonb_build_object(
      'accepted', false,
      'trip', jsonb_build_object(
        'tripId', v_trip.id,
        'publicId', v_trip.public_id,
        'name', v_trip.name,
        'status', v_trip.status,
        'startsOn', v_trip.starts_on,
        'endsOn', v_trip.ends_on
      ),
      'openSeats', coalesce((
        select jsonb_agg(jsonb_build_object(
          'tripPlayerId', tp.id,
          'displayName', tp.display_name,
          'role', tp.role
        ) order by tp.created_at)
        from public.trip_players tp
        where tp.trip_id = v_trip.id
          and tp.claimed_user_id is null
          and tp.rsvp <> 'no'
      ), '[]'::jsonb)
    ));
  end if;

  if v_trip.status = 'completed' then
    return tee_internal.api_error(v_request_id, 'claiming_closed', 'Roster claiming is closed for this trip.');
  end if;
  select * into v_player from public.trip_players tp
  where tp.id = p_trip_player_id and tp.trip_id = v_trip.id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  if v_player.claimed_user_id is not null then
    return tee_internal.api_error(v_request_id, 'seat_already_claimed', 'That roster spot has already been claimed.');
  end if;
  if v_invite.max_uses is not null and v_invite.use_count >= v_invite.max_uses then
    return tee_internal.api_error(v_request_id, 'invite_exhausted', 'This trip invitation has no claims remaining.');
  end if;

  update public.trip_players set claimed_user_id = v_user_id, rsvp = 'yes'
  where id = v_player.id;
  update public.trip_invites set use_count = use_count + 1 where id = v_invite.id;
  v_bootstrap := public.get_trip_bootstrap_v1(v_trip.id)->'data';
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'accepted', true,
    'tripId', v_trip.id,
    'tripPlayerId', v_player.id,
    'bootstrap', v_bootstrap
  ));
exception
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'claim_conflict', 'The roster changed while you were claiming. Refresh and try again.', true);
end;
$$;

revoke all on function public.accept_trip_invite_v1(text, uuid) from public;
grant execute on function public.accept_trip_invite_v1(text, uuid) to authenticated;
