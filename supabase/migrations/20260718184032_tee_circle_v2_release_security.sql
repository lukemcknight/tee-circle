set lock_timeout = '10s';
set statement_timeout = '5min';

-- Final native-v2 release security and delivery invariants.
--
-- This migration keeps payment provenance private, distinguishes TestFlight
-- purchases from production entitlements, makes invitation plaintext truly
-- one-shot, and leases ActivityKit delivery by monotonically increasing
-- canonical snapshot revision.


-- Purchase provenance -------------------------------------------------------

alter table public.trip_purchase_intents
  add column environment text,
  add column purchased_at timestamptz,
  add column cancelled_at timestamptz;

alter table public.trip_purchase_intents
  add constraint trip_purchase_intents_environment_check
  check (environment is null or environment in ('sandbox', 'production'));

alter table public.trip_entitlements
  add column environment text;

alter table public.trip_entitlements
  add constraint trip_entitlements_environment_check
  check (environment is null or environment in ('sandbox', 'production'));

comment on column public.trip_purchase_intents.environment is
  'RevenueCat-verified App Store environment. Null legacy rows fail closed.';
comment on column public.trip_entitlements.environment is
  'RevenueCat-verified App Store environment. Sandbox is active only behind the TestFlight runtime flag.';

insert into tee_internal.runtime_flags (key, enabled)
values ('sandbox_purchases_enabled', false)
on conflict (key) do nothing;

-- Transaction identifiers are server payment evidence, not trip-member data.
drop policy if exists "Trip members can read entitlements" on public.trip_entitlements;
revoke select on public.trip_entitlements from authenticated;

create or replace function tee_internal.trip_entitled_v1(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
  select exists (
    select 1
    from public.trip_entitlements te
    where te.trip_id = p_trip_id
      and (
        te.environment = 'production'
        or (
          te.environment = 'sandbox'
          and coalesce((
            select rf.enabled
            from tee_internal.runtime_flags rf
            where rf.key = 'sandbox_purchases_enabled'
          ), false)
        )
      )
  );
$$;

revoke all on function tee_internal.trip_entitled_v1(uuid) from public;

create or replace function tee_internal.trip_unlock_required_v1(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, tee_internal
as $$
  select coalesce((
    select rf.enabled
    from tee_internal.runtime_flags rf
    where rf.key = 'purchases_required'
  ), true) and not tee_internal.trip_entitled_v1(p_trip_id);
$$;

revoke all on function tee_internal.trip_unlock_required_v1(uuid) from public;

-- Preserve the established bootstrap DTO while replacing its legacy raw
-- entitlement EXISTS with a server-sanitized, environment-aware boolean.
alter function public.get_trip_bootstrap_v1(uuid)
  rename to get_trip_bootstrap_unfiltered_v1;
revoke all on function public.get_trip_bootstrap_unfiltered_v1(uuid)
  from public, anon, authenticated, service_role;
alter function public.get_trip_bootstrap_unfiltered_v1(uuid)
  set schema tee_internal;

create function public.get_trip_bootstrap_v1(p_trip_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_response jsonb;
begin
  v_response := tee_internal.get_trip_bootstrap_unfiltered_v1(p_trip_id);
  if v_response ? 'error' then
    return v_response;
  end if;
  return jsonb_set(
    v_response,
    '{data,trip,isUnlocked}',
    to_jsonb(tee_internal.trip_entitled_v1(p_trip_id)),
    true
  );
end;
$$;

-- Live Activity delivery ----------------------------------------------------

alter table public.live_activity_subscriptions
  add column last_delivered_revision bigint not null default -1,
  add column last_activity_timestamp bigint not null default 0,
  add column dispatching_revision bigint,
  add column dispatching_activity_timestamp bigint,
  add column dispatch_lease_id uuid,
  add column dispatch_lease_until timestamptz,
  add column last_delivery_attempt_at timestamptz;

alter table public.live_activity_subscriptions
  add constraint live_activity_last_delivered_revision_check
  check (last_delivered_revision >= -1),
  add constraint live_activity_last_timestamp_check
  check (last_activity_timestamp >= 0),
  add constraint live_activity_dispatching_revision_check
  check (dispatching_revision is null or dispatching_revision >= 0),
  add constraint live_activity_dispatch_lease_pair_check
  check (
    (
      dispatching_revision is null
      and dispatching_activity_timestamp is null
      and dispatch_lease_id is null
      and dispatch_lease_until is null
    )
    or (
      dispatching_revision is not null
      and dispatching_activity_timestamp is not null
      and dispatch_lease_id is not null
      and dispatch_lease_until is not null
    )
  );

with ranked as (
  select las.id,
    row_number() over (
      partition by las.user_id, las.device_id
      order by las.last_seen_at desc, las.created_at desc, las.id desc
    ) as rank
  from public.live_activity_subscriptions las
  where las.ended_at is null
)
update public.live_activity_subscriptions las
set ended_at = now(),
    dispatching_revision = null,
    dispatching_activity_timestamp = null,
    dispatch_lease_id = null,
    dispatch_lease_until = null
from ranked r
where r.id = las.id and r.rank > 1;

create unique index live_activity_one_active_user_device_key
  on public.live_activity_subscriptions (user_id, device_id)
  where ended_at is null;

create index live_activity_delivery_scan_idx
  on public.live_activity_subscriptions (
    coalesce(last_delivery_attempt_at, created_at), trip_id
  )
  where ended_at is null;

create or replace function public.register_live_activity_v1(
  p_trip_id uuid,
  p_device_id text,
  p_activity_id text,
  p_push_token text,
  p_environment text,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_id uuid;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found or not tee_internal.is_trip_member(p_trip_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if v_trip.status <> 'live' then
    return tee_internal.api_error(v_request_id, 'trip_not_live', 'Live Activities can only follow a live trip.');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text || ':' || coalesce(p_device_id, ''), 0)
  );
  update public.live_activity_subscriptions
  set ended_at = coalesce(ended_at, now()),
      dispatching_revision = null,
      dispatching_activity_timestamp = null,
      dispatch_lease_id = null,
      dispatch_lease_until = null
  where user_id = v_user_id
    and device_id = p_device_id
    and ended_at is null;

  insert into public.live_activity_subscriptions (
    trip_id, user_id, device_id, activity_id, push_token,
    environment, expires_at, last_seen_at, last_delivered_revision,
    last_activity_timestamp, dispatching_revision,
    dispatching_activity_timestamp, dispatch_lease_id,
    dispatch_lease_until, last_delivery_attempt_at,
    ended_at
  ) values (
    p_trip_id, v_user_id, p_device_id, p_activity_id, lower(p_push_token),
    p_environment, p_expires_at, now(), -1,
    0, null, null, null, null, null, null
  )
  on conflict (user_id, device_id, activity_id) do update set
    trip_id = excluded.trip_id,
    push_token = excluded.push_token,
    environment = excluded.environment,
    expires_at = excluded.expires_at,
    ended_at = null,
    last_seen_at = now(),
    last_delivered_revision = -1,
    -- A token refresh can reuse this row and must not move APS time backwards.
    last_activity_timestamp = public.live_activity_subscriptions.last_activity_timestamp,
    dispatching_revision = null,
    dispatching_activity_timestamp = null,
    dispatch_lease_id = null,
    dispatch_lease_until = null,
    last_delivery_attempt_at = null
  returning id into v_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'subscriptionId', v_id, 'tripId', p_trip_id, 'activityId', p_activity_id
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_activity_token', 'The Live Activity registration is invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'activity_token_conflict', 'That Live Activity registration conflicts with another active activity.', true);
end;
$$;

-- Atomically choose only subscriptions whose trip has a canonical snapshot at
-- the trip's current revision. A per-subscription lease prevents older and
-- newer APNs requests from being in flight together.
create or replace function public.lease_live_activity_deliveries_service_v1(
  p_trip_id uuid default null,
  p_requested_revision bigint default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_deliveries jsonb;
begin
  if p_limit is null or p_limit not between 1 and 100 then
    return tee_internal.api_error(v_request_id, 'invalid_limit', 'Delivery limit must be between 1 and 100.');
  end if;
  if (p_trip_id is null) <> (p_requested_revision is null)
     or (p_requested_revision is not null and p_requested_revision < 0) then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Trip and requested revision must be provided together.');
  end if;

  -- Expired or revoked members fail closed even if a dispatcher is delayed.
  update public.live_activity_subscriptions las
  set ended_at = coalesce(las.ended_at, now()),
      dispatching_revision = null,
      dispatching_activity_timestamp = null,
      dispatch_lease_id = null,
      dispatch_lease_until = null
  where las.ended_at is null
    and (
      (las.expires_at is not null and las.expires_at <= now())
      or not exists (
        select 1 from public.trip_players tp
        where tp.trip_id = las.trip_id
          and tp.claimed_user_id = las.user_id
          and tp.rsvp <> 'no'
      )
    );

  with ranked as materialized (
    select las.id, las.trip_id, s.revision,
      greatest(
        floor(extract(epoch from s.computed_at))::bigint,
        las.last_activity_timestamp + 1,
        floor(extract(epoch from now()))::bigint
      ) as activity_timestamp,
      coalesce(las.last_delivery_attempt_at, las.created_at) as delivery_order,
      row_number() over (
        partition by las.trip_id
        order by coalesce(las.last_delivery_attempt_at, las.created_at), las.id
      ) as trip_rank
    from public.live_activity_subscriptions las
    join public.trips t on t.id = las.trip_id
    join public.trip_leaderboard_snapshots s
      on s.trip_id = t.id and s.revision = t.score_revision
    where las.ended_at is null
      and (las.dispatch_lease_until is null or las.dispatch_lease_until <= now())
      and s.revision > las.last_delivered_revision
      and (p_trip_id is null or las.trip_id = p_trip_id)
      and (p_requested_revision is null or s.revision >= p_requested_revision)
  ), candidates as (
    select las.id, r.revision, r.activity_timestamp
    from public.live_activity_subscriptions las
    join ranked r on r.id = las.id
    where las.ended_at is null
      and (las.dispatch_lease_until is null or las.dispatch_lease_until <= now())
      and r.revision > las.last_delivered_revision
    -- Rank one from every trip precedes rank two from any trip, preventing a
    -- single large trip from monopolizing the scheduled global batch.
    order by r.trip_rank, r.delivery_order, r.trip_id, las.id
    for update of las skip locked
    limit p_limit
  ), leased as (
    update public.live_activity_subscriptions las
    set dispatching_revision = c.revision,
        dispatching_activity_timestamp = c.activity_timestamp,
        dispatch_lease_id = gen_random_uuid(),
        last_activity_timestamp = c.activity_timestamp,
        dispatch_lease_until = now() + interval '30 seconds',
        last_delivery_attempt_at = now()
    from candidates c
    where las.id = c.id
    returning las.*, c.revision as leased_revision,
      c.activity_timestamp as leased_activity_timestamp
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'subscriptionId', l.id,
    'tripId', l.trip_id,
    'userId', l.user_id,
    'activityId', l.activity_id,
    'pushToken', l.push_token,
    'environment', l.environment,
    'expiresAt', l.expires_at,
    'revision', l.leased_revision,
    'leaseId', l.dispatch_lease_id,
    'activityTimestamp', l.leased_activity_timestamp,
    'payload', s.payload,
    'computedAt', s.computed_at,
    'viewerPlayerId', (
      select tp.id
      from public.trip_players tp
      where tp.trip_id = l.trip_id
        and tp.claimed_user_id = l.user_id
        and tp.rsvp <> 'no'
      limit 1
    )
  ) order by coalesce(l.last_delivery_attempt_at, l.created_at), l.id), '[]'::jsonb)
  into v_deliveries
  from leased l
  join public.trip_leaderboard_snapshots s
    on s.trip_id = l.trip_id and s.revision = l.leased_revision;

  return tee_internal.api_success(v_request_id, jsonb_build_object('deliveries', v_deliveries));
end;
$$;

create or replace function public.complete_live_activity_delivery_service_v1(
  p_subscription_id uuid,
  p_revision bigint,
  p_lease_id uuid,
  p_outcome text,
  p_is_final boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_subscription public.live_activity_subscriptions%rowtype;
begin
  if p_subscription_id is null
     or p_revision is null or p_revision < 0
     or p_lease_id is null
     or p_outcome is null
     or p_outcome not in ('delivered', 'retry', 'terminal')
     or p_is_final is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'The delivery completion is invalid.');
  end if;
  select * into v_subscription
  from public.live_activity_subscriptions las
  where las.id = p_subscription_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'subscription_not_found', 'Live Activity subscription not found.');
  end if;
  if v_subscription.dispatching_revision is distinct from p_revision
     or v_subscription.dispatch_lease_id is distinct from p_lease_id then
    return tee_internal.api_success(v_request_id, jsonb_build_object(
      'subscriptionId', p_subscription_id,
      'status', 'stale_completion',
      'lastDeliveredRevision', v_subscription.last_delivered_revision
    ));
  end if;

  if p_outcome = 'delivered' then
    update public.live_activity_subscriptions
    set last_delivered_revision = greatest(last_delivered_revision, p_revision),
        last_seen_at = now(),
        ended_at = case when p_is_final then coalesce(ended_at, now()) else ended_at end,
        dispatching_revision = null,
        dispatching_activity_timestamp = null,
        dispatch_lease_id = null,
        dispatch_lease_until = null
    where id = p_subscription_id;
  elsif p_outcome = 'terminal' then
    update public.live_activity_subscriptions
    set ended_at = coalesce(ended_at, now()),
        dispatching_revision = null,
        dispatching_activity_timestamp = null,
        dispatch_lease_id = null,
        dispatch_lease_until = null
    where id = p_subscription_id;
  else
    update public.live_activity_subscriptions
    set dispatching_revision = null,
        dispatching_activity_timestamp = null,
        dispatch_lease_id = null,
        dispatch_lease_until = null
    where id = p_subscription_id;
  end if;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'subscriptionId', p_subscription_id,
    'status', p_outcome,
    'revision', p_revision,
    'final', p_is_final and p_outcome = 'delivered'
  ));
end;
$$;

alter function public.get_messages_bootstrap_service_v1(text)
  rename to get_messages_bootstrap_unfiltered_service_v1;
revoke all on function public.get_messages_bootstrap_unfiltered_service_v1(text)
  from public, anon, authenticated, service_role;
alter function public.get_messages_bootstrap_unfiltered_service_v1(text)
  set schema tee_internal;

create function public.get_messages_bootstrap_service_v1(p_token_hash_hex text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_response jsonb;
  v_trip_id uuid;
begin
  v_response := tee_internal.get_messages_bootstrap_unfiltered_service_v1(p_token_hash_hex);
  if v_response ? 'error' then
    return v_response;
  end if;
  v_trip_id := (v_response#>>'{data,trip,id}')::uuid;
  return jsonb_set(
    v_response,
    '{data,trip,isEntitled}',
    to_jsonb(tee_internal.trip_entitled_v1(v_trip_id)),
    true
  );
exception
  when invalid_text_representation then
    return tee_internal.api_error(gen_random_uuid(), 'invalid_bootstrap', 'The Messages trip response is invalid.', true);
end;
$$;

-- The existing lifecycle implementation still performs every atomic round
-- transition. This wrapper gates it on an eligible entitlement and prevents a
-- sandbox receipt stored during TestFlight from starting a public trip.
alter function public.start_trip_v1(uuid, bigint)
  rename to start_trip_unfiltered_v1;
revoke all on function public.start_trip_unfiltered_v1(uuid, bigint)
  from public, anon, authenticated, service_role;
alter function public.start_trip_unfiltered_v1(uuid, bigint)
  set schema tee_internal;

create function public.start_trip_v1(
  p_trip_id uuid,
  p_expected_score_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_purchases_required boolean;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can start this trip.');
  end if;
  select coalesce(rf.enabled, true) into v_purchases_required
  from tee_internal.runtime_flags rf
  where rf.key = 'purchases_required'
  for share;
  if coalesce(v_purchases_required, true)
     and not tee_internal.trip_entitled_v1(p_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_unlock_required', 'The captain must unlock this trip before scoring starts.');
  end if;
  return tee_internal.start_trip_unfiltered_v1(p_trip_id, p_expected_score_revision);
end;
$$;

-- TestFlight sandbox activation is reversible. Once its flag is disabled, an
-- already-live sandbox trip must also stop accepting scores/round transitions
-- until a production transaction replaces that entitlement.
alter function public.advance_trip_round_v1(uuid, uuid, bigint, boolean)
  rename to advance_trip_round_unfiltered_v1;
revoke all on function public.advance_trip_round_unfiltered_v1(uuid, uuid, bigint, boolean)
  from public, anon, authenticated, service_role;
alter function public.advance_trip_round_unfiltered_v1(uuid, uuid, bigint, boolean)
  set schema tee_internal;

create function public.advance_trip_round_v1(
  p_trip_id uuid,
  p_current_round_id uuid,
  p_expected_score_revision bigint default null,
  p_allow_incomplete boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if p_allow_incomplete is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'allowIncomplete must be true or false.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can advance this trip.');
  end if;
  if tee_internal.trip_unlock_required_v1(p_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_unlock_required', 'A production trip unlock is required before competition can continue.');
  end if;
  return tee_internal.advance_trip_round_unfiltered_v1(
    p_trip_id,
    p_current_round_id,
    p_expected_score_revision,
    p_allow_incomplete
  );
end;
$$;

alter function public.record_hole_score_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  rename to record_hole_score_unfiltered_v1;
revoke all on function public.record_hole_score_unfiltered_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  from public, anon, authenticated, service_role;
alter function public.record_hole_score_unfiltered_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  set schema tee_internal;

create function public.record_hole_score_v1(
  p_round_id uuid,
  p_trip_player_id uuid,
  p_hole_number smallint,
  p_strokes smallint,
  p_penalties smallint,
  p_idempotency_key uuid,
  p_expected_score_revision bigint default null
)
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
  v_round_trip_id uuid;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select r.trip_id into v_trip_id from public.rounds r where r.id = p_round_id;
  if not found or v_trip_id is null then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_trip_id for update;
  if not found or not tee_internal.is_trip_member(v_trip_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'forbidden', 'You cannot score for that trip.');
  end if;
  select r.trip_id into v_round_trip_id
  from public.rounds r
  where r.id = p_round_id and r.trip_id = v_trip.id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  perform 1 from public.trip_players tp
  where tp.id = p_trip_player_id and tp.trip_id = v_trip.id
  for update;
  if not found or not tee_internal.can_score_player(v_trip.id, p_trip_player_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'forbidden', 'You cannot score for that player.');
  end if;
  if tee_internal.trip_unlock_required_v1(v_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_unlock_required', 'A production trip unlock is required before scoring can continue.');
  end if;
  return tee_internal.record_hole_score_unfiltered_v1(
    p_round_id,
    p_trip_player_id,
    p_hole_number,
    p_strokes,
    p_penalties,
    p_idempotency_key,
    p_expected_score_revision
  );
end;
$$;

-- The service bridge temporarily impersonates the JWT-authenticated actor so
-- the command can reuse the exact RLS/role checks. Restore the caller's claim
-- before returning; pooled requests and later commands in the same transaction
-- must never inherit that identity.
create or replace function public.record_authenticated_hole_score_service_v1(
  p_actor_user_id uuid,
  p_round_id uuid,
  p_trip_player_id uuid,
  p_hole_number smallint,
  p_strokes smallint,
  p_penalties smallint,
  p_idempotency_key uuid,
  p_expected_score_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_previous_sub text := current_setting('request.jwt.claim.sub', true);
  v_response jsonb;
begin
  if p_actor_user_id is null
     or not exists (select 1 from auth.users u where u.id = p_actor_user_id) then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'A verified user is required.');
  end if;
  perform set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  begin
    v_response := public.record_hole_score_v1(
      p_round_id,
      p_trip_player_id,
      p_hole_number,
      p_strokes,
      p_penalties,
      p_idempotency_key,
      p_expected_score_revision
    );
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(v_previous_sub, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(v_previous_sub, ''), true);
  return v_response;
end;
$$;

alter function public.record_extension_hole_score_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  rename to record_extension_hole_score_unfiltered_service_v1;
revoke all on function public.record_extension_hole_score_unfiltered_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  from public, anon, authenticated, service_role;
alter function public.record_extension_hole_score_unfiltered_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  set schema tee_internal;

create function public.record_extension_hole_score_service_v1(
  p_token_hash_hex text,
  p_round_id uuid,
  p_trip_player_id uuid,
  p_hole_number smallint,
  p_strokes smallint,
  p_penalties smallint,
  p_idempotency_key uuid,
  p_expected_score_revision bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_trip_id uuid;
begin
  select s.trip_id into v_trip_id
  from public.extension_sessions s
  join public.trip_players tp
    on tp.id = s.trip_player_id
    and tp.trip_id = s.trip_id
    and tp.claimed_user_id = s.user_id
    and tp.rsvp <> 'no'
  where s.token_hash = decode(p_token_hash_hex, 'hex')
    and s.revoked_at is null
    and s.expires_at > now();
  if not found then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  perform 1 from public.trips t where t.id = v_trip_id for update;
  if not found or not exists (
    select 1
    from public.extension_sessions s
    join public.trip_players tp
      on tp.id = s.trip_player_id
      and tp.trip_id = s.trip_id
      and tp.claimed_user_id = s.user_id
      and tp.rsvp <> 'no'
    where s.token_hash = decode(p_token_hash_hex, 'hex')
      and s.trip_id = v_trip_id
      and s.revoked_at is null
      and s.expires_at > now()
  ) then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  if tee_internal.trip_unlock_required_v1(v_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_unlock_required', 'A production trip unlock is required before scoring can continue.');
  end if;
  return tee_internal.record_extension_hole_score_unfiltered_service_v1(
    p_token_hash_hex,
    p_round_id,
    p_trip_player_id,
    p_hole_number,
    p_strokes,
    p_penalties,
    p_idempotency_key,
    p_expected_score_revision
  );
exception
  when invalid_parameter_value or invalid_text_representation then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
end;
$$;

-- One pending StoreKit flow per account/product makes a crash-only webhook
-- unambiguous. Historical cancelled/expired intents remain as audit evidence.
update public.trip_purchase_intents
set status = 'expired'
where status = 'pending' and expires_at <= now();

with ranked as (
  select pi.id,
    row_number() over (
      partition by pi.user_id, pi.product_id
      order by pi.created_at desc, pi.id desc
    ) as rank
  from public.trip_purchase_intents pi
  where pi.status = 'pending'
)
update public.trip_purchase_intents pi
set status = 'expired'
from ranked r
where r.id = pi.id and r.rank > 1;

drop index if exists public.trip_purchase_intents_one_pending_trip_key;
create unique index trip_purchase_intents_one_pending_user_product_key
  on public.trip_purchase_intents (user_id, product_id)
  where status = 'pending';

create index if not exists trip_purchase_intents_webhook_window_idx
  on public.trip_purchase_intents (user_id, product_id, created_at desc, expires_at)
  where status in ('pending', 'expired', 'cancelled');

-- Invitation plaintext ------------------------------------------------------

-- Earlier development builds cached token-bearing responses. Scrub them
-- before replacing the command; hashes in trip_invites remain usable.
update tee_internal.command_idempotency
set response = response #- '{data,inviteToken}' #- '{data,url}'
where operation = 'create_trip_invite_v1';

create or replace function public.create_trip_invite_v1(
  p_trip_id uuid,
  p_expires_at timestamptz,
  p_max_uses integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_request jsonb := jsonb_build_object('tripId', p_trip_id, 'expiresAt', p_expires_at, 'maxUses', p_max_uses);
  v_hash bytea := tee_internal.request_hash(v_request);
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_token text;
  v_invite_id uuid;
  v_response jsonb;
  v_redacted jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An idempotency key is required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_trip_invite_v1' and v_existing.request_hash = v_hash then
      return tee_internal.api_error(
        v_request_id,
        'invite_token_already_issued',
        'This invitation token was returned once and cannot be replayed. Create a new invitation if the token was lost.',
        false,
        null,
        v_existing.response->'data'
      );
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;
  -- Serialize with ownership transfer, archive, and lifecycle changes before
  -- deciding whether this actor may mint a durable bearer credential.
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can create an invitation.');
  end if;
  if v_trip.status not in ('ready', 'live', 'completed') then
    return tee_internal.api_error(v_request_id, 'trip_not_shareable', 'Mark the trip ready before sharing it.');
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    return tee_internal.api_error(v_request_id, 'invalid_expiration', 'Invite expiration must be in the future.');
  end if;
  if p_max_uses is not null then
    return tee_internal.api_error(v_request_id, 'unsupported_option', 'Limited-use invitations are not available in version 1.');
  end if;

  -- Invitations may exist while the initial snapshot worker catches up. The
  -- public resolver already has an explicit leaderboard-updating state.
  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.trip_invites (
    trip_id, token_hash, created_by, expires_at, max_uses
  ) values (
    p_trip_id, extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), v_user_id, p_expires_at, p_max_uses
  ) returning id into v_invite_id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', v_invite_id,
    'inviteToken', v_token,
    'url', 'https://teecircle.vercel.app/t/' || v_token,
    'expiresAt', p_expires_at
  ));
  v_redacted := tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', v_invite_id,
    'expiresAt', p_expires_at,
    'tokenReplayable', false
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_invite_v1', v_hash, v_redacted);
  return v_response;
exception
  when check_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Invite settings are invalid.');
end;
$$;

-- Invitation operations ----------------------------------------------------

-- Captains can recover operational control from any signed-in device without
-- exposing bearer plaintext or token hashes.
create function public.list_trip_invites_v1(p_trip_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_invites jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for share;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can inspect invitations.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'inviteId', i.id,
    'createdAt', i.created_at,
    'expiresAt', i.expires_at,
    'revokedAt', i.revoked_at,
    'useCount', i.use_count,
    'maxUses', i.max_uses,
    'status', case
      when i.revoked_at is not null then 'revoked'
      when i.expires_at is not null and i.expires_at <= now() then 'expired'
      when i.max_uses is not null and i.use_count >= i.max_uses then 'exhausted'
      else 'active'
    end
  ) order by i.created_at desc, i.id desc), '[]'::jsonb)
  into v_invites
  from public.trip_invites i where i.trip_id = p_trip_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object('invites', v_invites));
end;
$$;

-- Revoke now follows the same trip -> invite lock order as create/rotate and
-- ownership transfer, preventing a former captain from winning a race.
create or replace function public.revoke_trip_invite_v1(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select i.trip_id into v_trip_id from public.trip_invites i where i.id = p_invite_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'invite_not_found', 'Invitation not found.');
  end if;
  perform 1 from public.trips t where t.id = v_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'invite_not_found', 'Invitation not found.');
  end if;
  if tee_internal.trip_role(v_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can revoke an invitation.');
  end if;
  perform 1 from public.trip_invites i
  where i.id = p_invite_id and i.trip_id = v_trip_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'invite_not_found', 'Invitation not found.');
  end if;
  update public.trip_invites set revoked_at = coalesce(revoked_at, now())
  where id = p_invite_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', p_invite_id,
    'revoked', true
  ));
end;
$$;

create function public.rotate_trip_invite_v1(
  p_trip_id uuid,
  p_expires_at timestamptz,
  p_max_uses integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_request jsonb := jsonb_build_object('tripId', p_trip_id, 'expiresAt', p_expires_at, 'maxUses', p_max_uses);
  v_hash bytea := tee_internal.request_hash(v_request);
  v_existing tee_internal.command_idempotency%rowtype;
  v_trip public.trips%rowtype;
  v_token text;
  v_invite_id uuid;
  v_revoked_count integer;
  v_response jsonb;
  v_redacted jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An idempotency key is required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'rotate_trip_invite_v1' and v_existing.request_hash = v_hash then
      return tee_internal.api_error(
        v_request_id,
        'invite_token_already_issued',
        'This replacement token was returned once and cannot be replayed. Rotate again if it was lost.',
        false,
        null,
        v_existing.response->'data'
      );
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can rotate invitations.');
  end if;
  if v_trip.status not in ('ready', 'live', 'completed') then
    return tee_internal.api_error(v_request_id, 'trip_not_shareable', 'Mark the trip ready before sharing it.');
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    return tee_internal.api_error(v_request_id, 'invalid_expiration', 'Invite expiration must be in the future.');
  end if;
  if p_max_uses is not null then
    return tee_internal.api_error(v_request_id, 'unsupported_option', 'Limited-use invitations are not available in version 1.');
  end if;

  update public.trip_invites i
  set revoked_at = coalesce(i.revoked_at, now())
  where i.trip_id = p_trip_id and i.revoked_at is null;
  get diagnostics v_revoked_count = row_count;

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.trip_invites (trip_id, token_hash, created_by, expires_at, max_uses)
  values (p_trip_id, extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), v_user_id, p_expires_at, p_max_uses)
  returning id into v_invite_id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', v_invite_id,
    'inviteToken', v_token,
    'url', 'https://teecircle.vercel.app/t/' || v_token,
    'expiresAt', p_expires_at,
    'revokedCount', v_revoked_count
  ));
  v_redacted := tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', v_invite_id,
    'expiresAt', p_expires_at,
    'revokedCount', v_revoked_count,
    'tokenReplayable', false
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'rotate_trip_invite_v1', v_hash, v_redacted);
  return v_response;
end;
$$;

-- Purchase commands ---------------------------------------------------------

create or replace function public.create_trip_purchase_intent_v1(
  p_trip_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_product_id constant text := 'com.teecircle.app.trip_unlock_2999';
  v_hash bytea := tee_internal.request_hash(jsonb_build_object('tripId', p_trip_id));
  v_existing tee_internal.command_idempotency%rowtype;
  v_intent public.trip_purchase_intents%rowtype;
  v_response jsonb;
  v_reused boolean := false;
  v_has_pending boolean := false;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An idempotency key is required.');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text || ':' || v_product_id, 0)
  );
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_trip_purchase_intent_v1'
       and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  perform 1 from public.trips t
  where t.id = p_trip_id and t.owner_id = v_user_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the trip captain can purchase the unlock.');
  end if;
  if tee_internal.trip_entitled_v1(p_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_already_unlocked', 'This trip is already unlocked.');
  end if;

  update public.trip_purchase_intents
  set status = 'expired'
  where user_id = v_user_id
    and product_id = v_product_id
    and status = 'pending'
    and expires_at <= now();

  select * into v_intent
  from public.trip_purchase_intents pi
  where pi.user_id = v_user_id
    and pi.product_id = v_product_id
    and pi.status = 'pending'
  order by pi.created_at desc, pi.id desc
  limit 1
  for update;
  v_has_pending := found;
  if tee_internal.trip_entitled_v1(p_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_already_unlocked', 'This trip was unlocked while the purchase flow was opening.');
  end if;
  if v_has_pending then
    if v_intent.trip_id <> p_trip_id then
      return tee_internal.api_error(
        v_request_id,
        'purchase_pending',
        'Finish or cancel the other pending trip purchase first.',
        false,
        null,
        jsonb_build_object(
          'purchaseIntentId', v_intent.id,
          'tripId', v_intent.trip_id,
          'expiresAt', v_intent.expires_at
        )
      );
    end if;
    v_reused := true;
  else
    insert into public.trip_purchase_intents (trip_id, user_id, product_id)
    values (p_trip_id, v_user_id, v_product_id)
    returning * into v_intent;
  end if;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'purchaseIntentId', v_intent.id,
    'tripId', v_intent.trip_id,
    'productId', v_intent.product_id,
    'expiresAt', v_intent.expires_at,
    'reusedPending', v_reused
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_purchase_intent_v1', v_hash, v_response);
  return v_response;
exception
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'purchase_intent_conflict', 'The purchase flow changed on another device. Retry to reuse it.', true);
end;
$$;

create or replace function public.cancel_trip_purchase_intent_v1(
  p_purchase_intent_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
  v_product_id text;
  v_intent public.trip_purchase_intents%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if p_purchase_intent_id is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'A purchase intent is required.');
  end if;
  select pi.trip_id, pi.product_id into v_trip_id, v_product_id
  from public.trip_purchase_intents pi
  where pi.id = p_purchase_intent_id and pi.user_id = v_user_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'purchase_intent_not_found', 'Purchase intent not found.');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text || ':' || v_product_id, 0)
  );
  perform 1 from public.trips t where t.id = v_trip_id for update;
  select * into v_intent
  from public.trip_purchase_intents pi
  where pi.id = p_purchase_intent_id and pi.user_id = v_user_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'purchase_intent_not_found', 'Purchase intent not found.');
  end if;
  if v_intent.status = 'verified' then
    return tee_internal.api_error(v_request_id, 'purchase_intent_already_claimed', 'This purchase has already unlocked its trip.');
  end if;
  if v_intent.status <> 'cancelled' then
    update public.trip_purchase_intents
    set status = 'cancelled', cancelled_at = coalesce(cancelled_at, now())
    where id = v_intent.id;
  end if;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'purchaseIntentId', v_intent.id,
    'tripId', v_intent.trip_id,
    'status', 'cancelled'
  ));
end;
$$;

-- Remove the pre-provenance service command so no caller can create an
-- environmentless entitlement after this migration.
revoke all on function public.verify_trip_purchase_v1(uuid, text, text, timestamptz)
  from public, anon, authenticated, service_role;
drop function public.verify_trip_purchase_v1(uuid, text, text, timestamptz);

create function public.verify_trip_purchase_v1(
  p_purchase_intent_id uuid,
  p_product_id text,
  p_revenuecat_transaction_id text,
  p_environment text,
  p_purchased_at timestamptz,
  p_verified_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_trip_id uuid;
  v_intent public.trip_purchase_intents%rowtype;
  v_existing public.trip_entitlements%rowtype;
  v_unlocked boolean;
begin
  select pi.trip_id into v_trip_id
  from public.trip_purchase_intents pi
  where pi.id = p_purchase_intent_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'purchase_intent_not_found', 'Purchase intent not found.');
  end if;
  -- Purchase creation/cancellation/verification all serialize trip then
  -- intent, so a just-verified unlock cannot race a second StoreKit flow.
  perform 1 from public.trips t where t.id = v_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'purchase_intent_not_found', 'Purchase intent not found.');
  end if;
  select * into v_intent
  from public.trip_purchase_intents pi
  where pi.id = p_purchase_intent_id and pi.trip_id = v_trip_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'purchase_intent_not_found', 'Purchase intent not found.');
  end if;
  if v_intent.status = 'verified' then
    if v_intent.revenuecat_transaction_id = p_revenuecat_transaction_id
       and v_intent.environment = p_environment then
      return tee_internal.api_success(v_request_id, jsonb_build_object(
        'tripId', v_intent.trip_id,
        'unlocked', tee_internal.trip_entitled_v1(v_intent.trip_id),
        'environment', v_intent.environment,
        'idempotentReplay', true
      ));
    end if;
    return tee_internal.api_error(v_request_id, 'purchase_intent_already_claimed', 'This intent is already linked to another transaction.');
  end if;
  if p_environment is null
     or p_environment not in ('sandbox', 'production')
     or p_product_id is null
     or p_product_id <> v_intent.product_id
     or p_verified_at is null
     or nullif(btrim(p_revenuecat_transaction_id), '') is null then
    return tee_internal.api_error(v_request_id, 'purchase_mismatch', 'The verified purchase does not match this trip unlock.');
  end if;
  if v_intent.status not in ('pending', 'expired', 'cancelled')
     or p_purchased_at is null
     or p_purchased_at < v_intent.created_at
     or p_purchased_at > v_intent.expires_at
     or p_purchased_at > now() + interval '5 minutes'
     or (
       v_intent.status = 'cancelled'
       and v_intent.cancelled_at is not null
       and p_purchased_at > v_intent.cancelled_at
     ) then
    return tee_internal.api_error(v_request_id, 'purchase_intent_expired', 'The verified purchase did not occur during this purchase intent.');
  end if;

  select * into v_existing
  from public.trip_entitlements te
  where te.trip_id = v_intent.trip_id
  for update;
  if found then
    if v_existing.revenuecat_transaction_id = p_revenuecat_transaction_id
       and v_existing.environment = p_environment then
      update public.trip_purchase_intents
      set status = 'verified',
          revenuecat_transaction_id = p_revenuecat_transaction_id,
          environment = p_environment,
          purchased_at = p_purchased_at,
          verified_at = p_verified_at
      where id = v_intent.id;
      return tee_internal.api_success(v_request_id, jsonb_build_object(
        'tripId', v_intent.trip_id,
        'unlocked', tee_internal.trip_entitled_v1(v_intent.trip_id),
        'environment', p_environment,
        'idempotentReplay', true
      ));
    end if;
    -- A real App Store purchase may replace a TestFlight/unknown entitlement
    -- on the same pre-release trip without discarding its verified intent row.
    if p_environment = 'production'
       and (v_existing.environment is null or v_existing.environment = 'sandbox') then
      delete from public.trip_entitlements te where te.trip_id = v_intent.trip_id;
    else
      return tee_internal.api_error(v_request_id, 'trip_already_unlocked', 'This trip is already linked to another verified purchase.');
    end if;
  end if;

  update public.trip_purchase_intents
  set status = 'verified',
      revenuecat_transaction_id = p_revenuecat_transaction_id,
      environment = p_environment,
      purchased_at = p_purchased_at,
      verified_at = p_verified_at
  where id = v_intent.id;
  insert into public.trip_entitlements (
    trip_id, purchase_intent_id, product_id,
    revenuecat_transaction_id, verified_at, environment
  ) values (
    v_intent.trip_id, v_intent.id, p_product_id,
    p_revenuecat_transaction_id, p_verified_at, p_environment
  );
  v_unlocked := tee_internal.trip_entitled_v1(v_intent.trip_id);
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_intent.trip_id,
    'unlocked', v_unlocked,
    'environment', p_environment,
    'idempotentReplay', false
  ));
exception
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'transaction_already_claimed', 'That App Store transaction already unlocked another trip.');
end;
$$;

-- Privilege boundary --------------------------------------------------------

drop policy if exists "Purchasers can read purchase intents"
  on public.trip_purchase_intents;
revoke select on table public.trip_purchase_intents from authenticated;

revoke all on function public.get_trip_bootstrap_v1(uuid) from public, anon;
revoke all on function public.get_messages_bootstrap_service_v1(text) from public, anon, authenticated;
revoke all on function public.start_trip_v1(uuid, bigint) from public, anon;
revoke all on function public.advance_trip_round_v1(uuid, uuid, bigint, boolean) from public, anon;
revoke all on function public.record_hole_score_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint) from public, anon, authenticated, service_role;
revoke all on function public.record_extension_hole_score_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint) from public, anon, authenticated;
revoke all on function public.create_trip_invite_v1(uuid, timestamptz, integer, uuid) from public, anon;
revoke all on function public.list_trip_invites_v1(uuid) from public, anon;
revoke all on function public.rotate_trip_invite_v1(uuid, timestamptz, integer, uuid) from public, anon;
revoke all on function public.revoke_trip_invite_v1(uuid) from public, anon;
revoke all on function public.create_trip_purchase_intent_v1(uuid, uuid) from public, anon;
revoke all on function public.cancel_trip_purchase_intent_v1(uuid) from public, anon;
revoke all on function public.register_live_activity_v1(uuid, text, text, text, text, timestamptz) from public, anon;
revoke all on function public.lease_live_activity_deliveries_service_v1(uuid, bigint, integer) from public, anon, authenticated;
revoke all on function public.complete_live_activity_delivery_service_v1(uuid, bigint, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.verify_trip_purchase_v1(uuid, text, text, text, timestamptz, timestamptz) from public, anon, authenticated;

grant execute on function public.get_trip_bootstrap_v1(uuid) to authenticated;
grant execute on function public.get_messages_bootstrap_service_v1(text) to service_role;
grant execute on function public.start_trip_v1(uuid, bigint) to authenticated;
grant execute on function public.advance_trip_round_v1(uuid, uuid, bigint, boolean) to authenticated;
grant execute on function public.record_extension_hole_score_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint) to service_role;
grant execute on function public.create_trip_invite_v1(uuid, timestamptz, integer, uuid) to authenticated;
grant execute on function public.list_trip_invites_v1(uuid) to authenticated;
grant execute on function public.rotate_trip_invite_v1(uuid, timestamptz, integer, uuid) to authenticated;
grant execute on function public.revoke_trip_invite_v1(uuid) to authenticated;
grant execute on function public.create_trip_purchase_intent_v1(uuid, uuid) to authenticated;
grant execute on function public.cancel_trip_purchase_intent_v1(uuid) to authenticated;
grant execute on function public.register_live_activity_v1(uuid, text, text, text, text, timestamptz) to authenticated;
grant execute on function public.lease_live_activity_deliveries_service_v1(uuid, bigint, integer) to service_role;
grant execute on function public.complete_live_activity_delivery_service_v1(uuid, bigint, uuid, text, boolean) to service_role;
grant execute on function public.verify_trip_purchase_v1(uuid, text, text, text, timestamptz, timestamptz) to service_role;
