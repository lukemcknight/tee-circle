set lock_timeout = '10s';
set statement_timeout = '5min';

-- Platform credentials, APNs/ActivityKit registrations, purchases, ownership,
-- and service-only snapshot worker commands.


create or replace function public.issue_extension_session_v1(
  p_trip_id uuid,
  p_device_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_player_id uuid;
  v_token text;
  v_session_id uuid;
  v_expires_at timestamptz := now() + interval '30 days';
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if char_length(coalesce(p_device_id, '')) not between 8 and 200 then
    return tee_internal.api_error(v_request_id, 'invalid_device_id', 'A stable device identifier is required.');
  end if;
  select tp.id into v_trip_player_id
  from public.trip_players tp join public.trips t on t.id = tp.trip_id
  where tp.trip_id = p_trip_id
    and tp.claimed_user_id = v_user_id
    and tp.rsvp <> 'no'
    and t.status not in ('archived')
  limit 1;
  if not found then
    return tee_internal.api_error(v_request_id, 'roster_claim_required', 'Claim a roster spot before connecting Messages.');
  end if;

  update public.extension_sessions set revoked_at = now()
  where user_id = v_user_id and device_id = p_device_id and revoked_at is null;
  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.extension_sessions (
    trip_id, user_id, trip_player_id, device_id, token_hash, expires_at
  ) values (
    p_trip_id, v_user_id, v_trip_player_id, p_device_id,
    extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), v_expires_at
  ) returning id into v_session_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'sessionId', v_session_id,
    'sessionToken', v_token,
    'tripId', p_trip_id,
    'tripPlayerId', v_trip_player_id,
    'expiresAt', v_expires_at
  ));
end;
$$;

create or replace function public.revoke_extension_session_v1(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  update public.extension_sessions set revoked_at = coalesce(revoked_at, now())
  where id = p_session_id and user_id = v_user_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'session_not_found', 'Extension session not found.');
  end if;
  return tee_internal.api_success(v_request_id, jsonb_build_object('sessionId', p_session_id, 'revoked', true));
end;
$$;

create or replace function tee_internal.resolve_extension_session_v1(p_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_session public.extension_sessions%rowtype;
begin
  select * into v_session from public.extension_sessions s
  where s.token_hash = p_token_hash
    and s.revoked_at is null and s.expires_at > now()
  for update;
  if not found then return null; end if;
  if not exists (
    select 1 from public.trip_players tp
    where tp.id = v_session.trip_player_id
      and tp.trip_id = v_session.trip_id
      and tp.claimed_user_id = v_session.user_id
      and tp.rsvp <> 'no'
  ) then
    update public.extension_sessions set revoked_at = now() where id = v_session.id;
    return null;
  end if;
  update public.extension_sessions set last_used_at = now() where id = v_session.id;
  return jsonb_build_object(
    'sessionId', v_session.id,
    'tripId', v_session.trip_id,
    'userId', v_session.user_id,
    'tripPlayerId', v_session.trip_player_id,
    'deviceId', v_session.device_id,
    'expiresAt', v_session.expires_at
  );
end;
$$;

create or replace function public.resolve_extension_session_service_v1(p_token_hash_hex text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
  select tee_internal.resolve_extension_session_v1(decode(p_token_hash_hex, 'hex'));
$$;

create or replace function public.register_device_push_v1(
  p_device_id text,
  p_token text,
  p_environment text,
  p_bundle_id text default 'com.teecircle.app'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_id uuid;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if p_bundle_id is distinct from 'com.teecircle.app' then
    return tee_internal.api_error(v_request_id, 'invalid_bundle_id', 'This bundle cannot register app notifications.');
  end if;
  insert into public.native_device_tokens (
    user_id, device_id, provider, token, environment, bundle_id,
    last_seen_at, disabled_at
  ) values (
    v_user_id, p_device_id, 'apns', lower(p_token), p_environment, p_bundle_id,
    now(), null
  )
  on conflict (user_id, device_id, provider, environment, bundle_id) do update set
    token = excluded.token,
    last_seen_at = now(),
    disabled_at = null
  returning id into v_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'registrationId', v_id, 'provider', 'apns', 'environment', p_environment
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_push_token', 'The APNs registration is invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'push_token_conflict', 'That APNs token is already registered to another device.');
end;
$$;

create or replace function public.unregister_device_push_v1(
  p_device_id text,
  p_environment text,
  p_bundle_id text default 'com.teecircle.app'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  update public.native_device_tokens set disabled_at = now()
  where user_id = v_user_id and device_id = p_device_id
    and environment = p_environment and bundle_id = p_bundle_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object('disabled', true));
end;
$$;

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
  select * into v_trip from public.trips t where t.id = p_trip_id;
  if not found or not tee_internal.is_trip_member(p_trip_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if v_trip.status <> 'live' then
    return tee_internal.api_error(v_request_id, 'trip_not_live', 'Live Activities can only follow a live trip.');
  end if;
  -- V1 intentionally supports one active TeeCircle activity per device.
  update public.live_activity_subscriptions set ended_at = coalesce(ended_at, now())
  where user_id = v_user_id and device_id = p_device_id and ended_at is null;
  insert into public.live_activity_subscriptions (
    trip_id, user_id, device_id, activity_id, push_token,
    environment, expires_at, last_seen_at
  ) values (
    p_trip_id, v_user_id, p_device_id, p_activity_id, lower(p_push_token),
    p_environment, p_expires_at, now()
  )
  on conflict (user_id, device_id, activity_id) do update set
    trip_id = excluded.trip_id,
    push_token = excluded.push_token,
    environment = excluded.environment,
    expires_at = excluded.expires_at,
    ended_at = null,
    last_seen_at = now()
  returning id into v_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'subscriptionId', v_id, 'tripId', p_trip_id, 'activityId', p_activity_id
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_activity_token', 'The Live Activity registration is invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'activity_token_conflict', 'That Live Activity token is already registered.');
end;
$$;

create or replace function public.end_live_activity_v1(p_activity_id text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  update public.live_activity_subscriptions set ended_at = coalesce(ended_at, now())
  where user_id = v_user_id and activity_id = p_activity_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object('activityId', p_activity_id, 'ended', true));
end;
$$;

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
  v_hash bytea := tee_internal.request_hash(jsonb_build_object('tripId', p_trip_id));
  v_existing tee_internal.command_idempotency%rowtype;
  v_intent public.trip_purchase_intents%rowtype;
  v_response jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if p_idempotency_key is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'An idempotency key is required.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || p_idempotency_key::text, 0));
  select * into v_existing from tee_internal.command_idempotency ci
  where ci.user_id = v_user_id and ci.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operation = 'create_trip_purchase_intent_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;
  if not exists (
    select 1 from public.trips t where t.id = p_trip_id and t.owner_id = v_user_id
  ) then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the trip captain can purchase the unlock.');
  end if;
  if exists (select 1 from public.trip_entitlements te where te.trip_id = p_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_already_unlocked', 'This trip is already unlocked.');
  end if;
  update public.trip_purchase_intents set status = 'expired'
  where trip_id = p_trip_id and user_id = v_user_id
    and status = 'pending' and expires_at <= now();
  insert into public.trip_purchase_intents (trip_id, user_id)
  values (p_trip_id, v_user_id) returning * into v_intent;
  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'purchaseIntentId', v_intent.id,
    'tripId', v_intent.trip_id,
    'productId', v_intent.product_id,
    'expiresAt', v_intent.expires_at
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_purchase_intent_v1', v_hash, v_response);
  return v_response;
end;
$$;

-- Called only after the server has independently verified RevenueCat's event
-- or REST response. Client roles have no EXECUTE privilege on this function.
create or replace function public.verify_trip_purchase_v1(
  p_purchase_intent_id uuid,
  p_product_id text,
  p_revenuecat_transaction_id text,
  p_verified_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_intent public.trip_purchase_intents%rowtype;
begin
  select * into v_intent from public.trip_purchase_intents pi
  where pi.id = p_purchase_intent_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'purchase_intent_not_found', 'Purchase intent not found.');
  end if;
  if v_intent.status = 'verified' then
    if v_intent.revenuecat_transaction_id = p_revenuecat_transaction_id then
      return tee_internal.api_success(v_request_id, jsonb_build_object(
        'tripId', v_intent.trip_id, 'unlocked', true, 'idempotentReplay', true
      ));
    end if;
    return tee_internal.api_error(v_request_id, 'purchase_intent_already_claimed', 'This intent is already linked to another transaction.');
  end if;
  if v_intent.status <> 'pending' or v_intent.expires_at <= now() then
    return tee_internal.api_error(v_request_id, 'purchase_intent_expired', 'Create a new purchase intent and retry verification.');
  end if;
  if p_product_id <> v_intent.product_id or nullif(btrim(p_revenuecat_transaction_id), '') is null then
    return tee_internal.api_error(v_request_id, 'purchase_mismatch', 'The verified purchase does not match this trip unlock.');
  end if;

  update public.trip_purchase_intents set
    status = 'verified',
    revenuecat_transaction_id = p_revenuecat_transaction_id,
    verified_at = p_verified_at
  where id = v_intent.id;
  insert into public.trip_entitlements (
    trip_id, purchase_intent_id, product_id,
    revenuecat_transaction_id, verified_at
  ) values (
    v_intent.trip_id, v_intent.id, p_product_id,
    p_revenuecat_transaction_id, p_verified_at
  );
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_intent.trip_id, 'unlocked', true, 'idempotentReplay', false
  ));
exception
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'transaction_already_claimed', 'That App Store transaction already unlocked another trip.');
end;
$$;

create or replace function public.transfer_trip_ownership_v1(
  p_trip_id uuid,
  p_new_owner_trip_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_new_user_id uuid;
  v_old_player_id uuid;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  perform 1 from public.trips t where t.id = p_trip_id and t.owner_id = v_user_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can transfer this trip.');
  end if;
  select tp.claimed_user_id into v_new_user_id from public.trip_players tp
  where tp.id = p_new_owner_trip_player_id and tp.trip_id = p_trip_id and tp.claimed_user_id is not null
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'claimed_player_required', 'Transfer ownership to a claimed roster player.');
  end if;
  select tp.id into v_old_player_id from public.trip_players tp
  where tp.trip_id = p_trip_id and tp.claimed_user_id = v_user_id for update;
  update public.trip_players set role = 'player' where id = v_old_player_id;
  update public.trip_players set role = 'captain' where id = p_new_owner_trip_player_id;
  update public.trips set owner_id = v_new_user_id where id = p_trip_id;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'newOwnerTripPlayerId', p_new_owner_trip_player_id
  ));
end;
$$;

create or replace function public.get_account_deletion_blockers_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_blockers jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'tripId', t.id, 'name', t.name, 'status', t.status
  ) order by t.starts_on), '[]'::jsonb) into v_blockers
  from public.trips t
  where t.owner_id = v_user_id and t.status <> 'archived';
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'canDelete', jsonb_array_length(v_blockers) = 0,
    'ownedTrips', v_blockers
  ));
end;
$$;

-- Worker RPCs ----------------------------------------------------------------

create or replace function public.lease_trip_snapshot_jobs_v1(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_jobs jsonb;
begin
  if p_limit is null or p_limit not between 1 and 50 then
    return tee_internal.api_error(v_request_id, 'invalid_limit', 'Worker limit must be between 1 and 50.');
  end if;
  with ranked as (
    select j.trip_id, j.revision,
      row_number() over (partition by j.trip_id order by j.revision desc) as rank
    from tee_internal.leaderboard_recompute_jobs j
    where j.available_at <= now()
      and (
        j.status in ('pending', 'failed')
        or (j.status = 'processing' and j.leased_until < now())
      )
  ), candidates as (
    select j.trip_id, j.revision
    from tee_internal.leaderboard_recompute_jobs j
    join ranked r on r.trip_id = j.trip_id and r.revision = j.revision and r.rank = 1
    order by j.created_at
    for update of j skip locked
    limit p_limit
  ), leased as (
    update tee_internal.leaderboard_recompute_jobs j set
      status = 'processing',
      attempts = j.attempts + 1,
      leased_until = now() + interval '60 seconds',
      last_error = null
    from candidates c
    where j.trip_id = c.trip_id and j.revision = c.revision
    returning j.trip_id, j.revision, j.attempts
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'tripId', l.trip_id, 'revision', l.revision, 'attempt', l.attempts
  )), '[]'::jsonb) into v_jobs from leased l;
  return tee_internal.api_success(v_request_id, jsonb_build_object('jobs', v_jobs));
end;
$$;

create or replace function public.get_trip_scoring_input_v1(p_trip_id uuid, p_revision bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_trip public.trips%rowtype;
  v_data jsonb;
begin
  select * into v_trip from public.trips t where t.id = p_trip_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if v_trip.score_revision is distinct from p_revision then
    return tee_internal.api_error(v_request_id, 'stale_revision', 'A newer trip revision must be computed.', true, v_trip.score_revision);
  end if;

  select jsonb_build_object(
    'trip', jsonb_build_object(
      'id', v_trip.id,
      'publicId', v_trip.public_id,
      'name', v_trip.name,
      'status', v_trip.status,
      'enabledFormats', v_trip.enabled_formats,
      'primaryFormat', v_trip.primary_format,
      'scoringMode', v_trip.scoring_mode,
      'revision', v_trip.score_revision
    ),
    'rounds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'roundId', r.id,
        'publicId', r.public_id,
        'name', r.course_name,
        'status', r.trip_round_status,
        'tripOrder', r.trip_order,
        'players', coalesce((
          select jsonb_agg(jsonb_build_object(
            'playerId', tp.id,
            'displayName', tp.display_name,
            'courseHandicap', coalesce(trp.playing_handicap, trp.course_handicap, 0),
            'holes', coalesce((
              select jsonb_agg(jsonb_build_object(
                'hole', rh.hole_number,
                'par', rh.par,
                'strokeIndex', rh.stroke_index,
                'strokes', s.strokes
              ) order by rh.hole_number)
              from public.round_holes rh
              left join public.trip_hole_scores s
                on s.round_id = rh.round_id
                and s.hole_number = rh.hole_number
                and s.trip_player_id = tp.id
              where rh.round_id = r.id
            ), '[]'::jsonb)
          ) order by tp.created_at)
          from public.trip_round_players trp
          join public.trip_players tp on tp.id = trp.trip_player_id
          where trp.round_id = r.id and trp.status = 'active'
        ), '[]'::jsonb)
      ) order by r.trip_order)
      from public.rounds r where r.trip_id = v_trip.id
    ), '[]'::jsonb)
  ) into v_data;
  return tee_internal.api_success(v_request_id, v_data);
end;
$$;

create or replace function public.persist_trip_snapshot_v1(
  p_trip_id uuid,
  p_revision bigint,
  p_payload jsonb,
  p_scoring_engine_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if p_revision is null then
    return tee_internal.api_error(v_request_id, 'invalid_snapshot', 'Snapshot identity or schema version is invalid.');
  end if;
  if v_trip.score_revision is distinct from p_revision then
    insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
    values (p_trip_id, v_trip.score_revision)
    on conflict (trip_id, revision) do update
      set status = 'pending', available_at = now(), leased_until = null;
    return tee_internal.api_error(v_request_id, 'stale_revision', 'Snapshot is older than the trip.', true, v_trip.score_revision);
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload) is distinct from 'object'
     or jsonb_typeof(p_payload->'schemaVersion') is distinct from 'number'
     or p_payload->>'schemaVersion' is distinct from '1'
     or jsonb_typeof(p_payload->'revision') is distinct from 'number'
     or p_payload->'revision' is distinct from to_jsonb(p_revision)
     or jsonb_typeof(p_payload->'tripId') is distinct from 'string'
     or p_payload->>'tripId' is distinct from v_trip.public_id::text then
    return tee_internal.api_error(v_request_id, 'invalid_snapshot', 'Snapshot identity or schema version is invalid.');
  end if;
  if p_scoring_engine_version is distinct from 'tee-circle-ts-2' then
    return tee_internal.api_error(v_request_id, 'unsupported_scoring_engine', 'Only the current scoring engine may persist a canonical snapshot.');
  end if;

  insert into public.trip_leaderboard_snapshots (
    trip_id, revision, scoring_engine_version, payload, is_final
  ) values (
    p_trip_id, p_revision, p_scoring_engine_version, p_payload, v_trip.status = 'completed'
  )
  on conflict (trip_id, revision) do update set
    scoring_engine_version = excluded.scoring_engine_version,
    payload = excluded.payload,
    is_final = excluded.is_final,
    computed_at = now();
  update tee_internal.leaderboard_recompute_jobs set
    status = 'completed', completed_at = now(), leased_until = null
  where trip_id = p_trip_id and revision <= p_revision and status <> 'completed';
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'revision', p_revision,
    'isFinal', v_trip.status = 'completed'
  ));
exception
  when invalid_text_representation then
    return tee_internal.api_error(v_request_id, 'invalid_snapshot', 'Snapshot identity or schema version is invalid.');
end;
$$;

create or replace function public.fail_trip_snapshot_job_v1(
  p_trip_id uuid,
  p_revision bigint,
  p_error text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
begin
  update tee_internal.leaderboard_recompute_jobs set
    status = case when attempts >= 25 then 'failed' else 'pending' end,
    available_at = now() + make_interval(secs => least(300, greatest(5, attempts * 10))),
    leased_until = null,
    last_error = left(coalesce(p_error, 'unknown worker error'), 1000)
  where trip_id = p_trip_id and revision = p_revision;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id, 'revision', p_revision, 'retryScheduled', found
  ));
end;
$$;

revoke all on function public.issue_extension_session_v1(uuid, text) from public;
revoke all on function public.revoke_extension_session_v1(uuid) from public;
revoke all on function tee_internal.resolve_extension_session_v1(bytea) from public;
revoke all on function public.resolve_extension_session_service_v1(text) from public;
revoke all on function public.register_device_push_v1(text, text, text, text) from public;
revoke all on function public.unregister_device_push_v1(text, text, text) from public;
revoke all on function public.register_live_activity_v1(uuid, text, text, text, text, timestamptz) from public;
revoke all on function public.end_live_activity_v1(text) from public;
revoke all on function public.create_trip_purchase_intent_v1(uuid, uuid) from public;
revoke all on function public.verify_trip_purchase_v1(uuid, text, text, timestamptz) from public;
revoke all on function public.transfer_trip_ownership_v1(uuid, uuid) from public;
revoke all on function public.get_account_deletion_blockers_v1() from public;
revoke all on function public.lease_trip_snapshot_jobs_v1(integer) from public;
revoke all on function public.get_trip_scoring_input_v1(uuid, bigint) from public;
revoke all on function public.persist_trip_snapshot_v1(uuid, bigint, jsonb, text) from public;
revoke all on function public.fail_trip_snapshot_job_v1(uuid, bigint, text) from public;

grant execute on function public.issue_extension_session_v1(uuid, text) to authenticated;
grant execute on function public.revoke_extension_session_v1(uuid) to authenticated;
grant execute on function tee_internal.resolve_extension_session_v1(bytea) to service_role;
grant execute on function public.resolve_extension_session_service_v1(text) to service_role;
grant execute on function public.register_device_push_v1(text, text, text, text) to authenticated;
grant execute on function public.unregister_device_push_v1(text, text, text) to authenticated;
grant execute on function public.register_live_activity_v1(uuid, text, text, text, text, timestamptz) to authenticated;
grant execute on function public.end_live_activity_v1(text) to authenticated;
grant execute on function public.create_trip_purchase_intent_v1(uuid, uuid) to authenticated;
grant execute on function public.verify_trip_purchase_v1(uuid, text, text, timestamptz) to service_role;
grant execute on function public.transfer_trip_ownership_v1(uuid, uuid) to authenticated;
grant execute on function public.get_account_deletion_blockers_v1() to authenticated;
grant execute on function public.lease_trip_snapshot_jobs_v1(integer) to service_role;
grant execute on function public.get_trip_scoring_input_v1(uuid, bigint) to service_role;
grant execute on function public.persist_trip_snapshot_v1(uuid, bigint, jsonb, text) to service_role;
grant execute on function public.fail_trip_snapshot_job_v1(uuid, bigint, text) to service_role;
