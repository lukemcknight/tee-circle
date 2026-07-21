set lock_timeout = '10s';
set statement_timeout = '5min';

-- RSVP decline for a claimed roster seat. The data model has no per-invitee
-- record before a claim (accept_trip_invite_v1 only lists open seats), so
-- decline is a first-person action by the claimed player: release the claim
-- and mark rsvp 'no', mirroring release_trip_player_claim_v1's locking and
-- session/activity teardown. is_trip_member filters rsvp <> 'no', so a
-- declined player intentionally loses trip access; the captain can re-open
-- the seat with update_trip_player_v1.

create or replace function public.decline_trip_seat_v1(p_trip_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
  v_trip public.trips%rowtype;
  v_player public.trip_players%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  -- Match release_trip_player_claim_v1: lock the trip before the roster seat.
  select tp.trip_id into v_trip_id from public.trip_players tp
  where tp.id = p_trip_player_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  select * into v_player from public.trip_players tp
  where tp.id = p_trip_player_id and tp.trip_id = v_trip.id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  if v_player.role = 'captain' then
    return tee_internal.api_error(v_request_id, 'captain_claim_required', 'Transfer trip ownership before declining the captain seat.');
  end if;
  if v_player.claimed_user_id is distinct from v_user_id then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the player who claimed this seat can decline it.');
  end if;
  if v_trip.status = 'archived' then
    return tee_internal.api_error(v_request_id, 'trip_archived', 'Archived trips cannot change roster claims.');
  end if;

  update public.trip_players
  set claimed_user_id = null, rsvp = 'no'
  where id = v_player.id;
  update public.extension_sessions set revoked_at = now()
  where trip_player_id = v_player.id and revoked_at is null;
  update public.live_activity_subscriptions set ended_at = coalesce(ended_at, now())
  where trip_id = v_player.trip_id
    and user_id = v_user_id
    and ended_at is null;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_player.trip_id,
    'tripPlayerId', v_player.id,
    'rsvp', 'no',
    'claimed', false
  ));
end;
$$;

-- Revoke the implicit hosted grants (postgres default privileges hand
-- anon/authenticated/service_role direct EXECUTE on every new function), then
-- restore only the signed-in entry point.
revoke all on function public.decline_trip_seat_v1(uuid) from public, anon, authenticated, service_role;
grant execute on function public.decline_trip_seat_v1(uuid) to authenticated;
