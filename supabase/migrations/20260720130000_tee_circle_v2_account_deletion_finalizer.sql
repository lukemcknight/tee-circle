set lock_timeout = '10s';
set statement_timeout = '5min';

-- Native account deletion, SQL half. finalize_account_deletion_v1 re-checks
-- the same blockers get_account_deletion_blockers_v1 reports, then removes or
-- detaches every row that references the caller so a follow-up service-role
-- Auth Admin deletion of auth.users cannot hit a FK wall. It deliberately does
-- NOT touch auth.users: only the delete-account-v1 edge function's
-- service-role client may do that. The legacy public.delete_user_account()
-- keeps failing closed for native members and is not changed here.

create or replace function public.finalize_account_deletion_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_blocker_count integer;
  v_owned_trip_count integer;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;

  -- Serialize a double-tapped delete; the second call finds nothing to do.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':finalize_account_deletion_v1', 0));

  select count(*) into v_blocker_count
  from public.trips t
  where t.owner_id = v_user_id and t.status in ('draft', 'ready', 'live');
  if v_blocker_count > 0 then
    return tee_internal.api_error(
      v_request_id,
      'account_deletion_blocked',
      'Transfer or archive your active trips before deleting your account.'
    );
  end if;

  select count(*) into v_owned_trip_count
  from public.trips t where t.owner_id = v_user_id;

  -- 1) Owned completed/archived trips: clear restrict-protected satellites in
  --    dependency order, then the trips themselves.
  delete from public.trip_score_audit a
  using public.trips t
  where t.owner_id = v_user_id and a.trip_id = t.id;

  delete from public.trip_hole_scores s
  using public.trips t
  where t.owner_id = v_user_id and s.trip_id = t.id;

  delete from public.trip_entitlements te
  using public.trips t
  where t.owner_id = v_user_id and te.trip_id = t.id;

  delete from public.trip_purchase_intents pi
  using public.trips t
  where t.owner_id = v_user_id and pi.trip_id = t.id;

  delete from public.trip_invites i
  using public.trips t
  where t.owner_id = v_user_id and i.trip_id = t.id;

  delete from public.extension_sessions es
  using public.trips t
  where t.owner_id = v_user_id and es.trip_id = t.id;

  delete from public.live_activity_subscriptions las
  using public.trips t
  where t.owner_id = v_user_id and las.trip_id = t.id;

  delete from public.trip_leaderboard_snapshots snap
  using public.trips t
  where t.owner_id = v_user_id and snap.trip_id = t.id;

  delete from tee_internal.leaderboard_recompute_jobs j
  using public.trips t
  where t.owner_id = v_user_id and j.trip_id = t.id;

  delete from public.round_responses rr
  using public.rounds r, public.trips t
  where t.owner_id = v_user_id and r.trip_id = t.id and rr.round_id = r.id;

  -- rounds -> trips is on delete restrict; legacy scorecards cascade off
  -- rounds per the audited baseline contract.
  delete from public.rounds r
  using public.trips t
  where t.owner_id = v_user_id and r.trip_id = t.id;

  delete from public.trip_players tp
  using public.trips t
  where t.owner_id = v_user_id and tp.trip_id = t.id;

  delete from public.trips t where t.owner_id = v_user_id;

  -- 2) Seats claimed on surviving trips: release the claim exactly like
  --    release_trip_player_claim_v1. The seat, its display name, and its
  --    scores remain the group's data.
  update public.trip_players tp
  set claimed_user_id = null
  where tp.claimed_user_id = v_user_id;

  -- 3) Reattribute authorship a surviving group still needs (RESTRICT FKs to
  --    auth.users). Fresh idempotency keys dodge the (user, key) uniques.
  update public.trip_hole_scores s
  set recorded_by_user_id = t.owner_id, idempotency_key = gen_random_uuid()
  from public.trips t
  where s.trip_id = t.id and s.recorded_by_user_id = v_user_id;

  update public.trip_score_audit a
  set actor_user_id = t.owner_id, idempotency_key = gen_random_uuid()
  from public.trips t
  where a.trip_id = t.id and a.actor_user_id = v_user_id;

  update public.trip_invites i
  set created_by = t.owner_id
  from public.trips t
  where i.trip_id = t.id and i.created_by = v_user_id;

  update public.trip_purchase_intents pi
  set user_id = t.owner_id
  from public.trips t
  where pi.trip_id = t.id and pi.user_id = v_user_id;

  -- created_by is nullable and references profiles with NO ACTION; leaving it
  -- set would block the profiles delete below (and the auth cascade later).
  update public.rounds r
  set created_by = null
  where r.created_by = v_user_id and r.trip_id is not null;

  -- 4) Personal artifacts everywhere (course_card_holes cascade off cards).
  delete from public.extension_sessions where user_id = v_user_id;
  delete from public.native_device_tokens where user_id = v_user_id;
  delete from public.live_activity_subscriptions where user_id = v_user_id;
  delete from tee_internal.command_idempotency where user_id = v_user_id;
  delete from public.course_cards where owner_id = v_user_id;

  -- 5) Legacy cleanup: the same statements as public.delete_user_account,
  --    which fails closed for native members and therefore cannot be reused.
  delete from public.friendships where user_low = v_user_id or user_high = v_user_id;
  delete from public.group_members where user_id = v_user_id;
  delete from public.round_responses where user_id = v_user_id;
  if to_regclass('public.push_tokens') is not null then
    delete from public.push_tokens where user_id = v_user_id;
  end if;
  delete from public.rounds where created_by = v_user_id and trip_id is null;
  delete from public.groups where created_by = v_user_id;
  delete from public.profiles where id = v_user_id;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'finalized', true,
    'deletedOwnedTrips', v_owned_trip_count
  ));
end;
$$;

-- Match the ACL posture established in the function hardening migration:
-- revoke the implicit hosted grants (postgres default privileges hand
-- anon/authenticated/service_role direct EXECUTE on every new function), then
-- restore only the signed-in entry point.
revoke all on function public.finalize_account_deletion_v1() from public, anon, authenticated, service_role;
grant execute on function public.finalize_account_deletion_v1() to authenticated;
