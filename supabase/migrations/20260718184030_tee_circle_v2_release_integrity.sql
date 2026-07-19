set lock_timeout = '10s';
set statement_timeout = '5min';

-- Release-integrity hardening for the native 2.0 command surface.
--
-- This migration is intentionally additive. It closes client privilege
-- bypasses, makes trip/round lifecycle changes atomic, preserves independent
-- Messages sessions per trip, and tightens the canonical scoring contract.


-- Roster onboarding must prove possession of a live invitation. Captains and
-- players retain the separate release/reassign command.
revoke all on function public.claim_trip_player_v1(uuid) from public, anon, authenticated;

-- The native model intentionally reuses the legacy rounds table so the Expo
-- rollback remains buildable. Legacy client policies may only operate on
-- legacy rows; all rows attached to a trip are command-only. Restrictive
-- policies are ANDed with every pre-existing permissive Expo policy.
drop policy if exists "Native trip rounds block direct inserts" on public.rounds;
drop policy if exists "Native trip rounds block direct updates" on public.rounds;
drop policy if exists "Native trip rounds block direct deletes" on public.rounds;

create policy "Native trip rounds block direct inserts"
on public.rounds as restrictive
for insert to authenticated
with check (trip_id is null);

create policy "Native trip rounds block direct updates"
on public.rounds as restrictive
for update to authenticated
using (trip_id is null)
with check (trip_id is null);

create policy "Native trip rounds block direct deletes"
on public.rounds as restrictive
for delete to authenticated
using (trip_id is null);

-- Preserve the Expo delete RPC but fail closed for native rows. SECURITY
-- DEFINER bypasses RLS, so this explicit trip_id guard is required as well.
create or replace function public.delete_round(p_round_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_created_by uuid;
begin
  select r.created_by into v_created_by
  from public.rounds r
  where r.id = p_round_id and r.trip_id is null;

  if v_created_by is null or v_created_by <> auth.uid() then
    return false;
  end if;

  delete from public.round_responses rr where rr.round_id = p_round_id;
  delete from public.rounds r
  where r.id = p_round_id
    and r.created_by = auth.uid()
    and r.trip_id is null;
  return found;
end;
$$;

revoke all on function public.delete_round(uuid) from public, anon;
grant execute on function public.delete_round(uuid) to authenticated;

-- Only one unrevoked Messages credential may exist for the same trip seat on
-- one user's device. An expired row is revoked by the next issuance before the
-- replacement is inserted.
with ranked as (
  select s.id,
    row_number() over (
      partition by s.user_id, s.device_id, s.trip_id
      order by s.created_at desc, s.id desc
    ) as rank
  from public.extension_sessions s
  where s.revoked_at is null
)
update public.extension_sessions s
set revoked_at = now()
from ranked r
where r.id = s.id and r.rank > 1;

create unique index if not exists extension_sessions_active_trip_device_key
  on public.extension_sessions (user_id, device_id, trip_id)
  where revoked_at is null;

-- A trip has exactly one purchase flow waiting for StoreKit/RevenueCat. Keep
-- the oldest still-valid intent so an already-started purchase remains
-- claimable, and expire any ambiguous duplicate rows before adding the guard.
update public.trip_purchase_intents
set status = 'expired'
where status = 'pending' and expires_at <= now();

with ranked as (
  select pi.id,
    row_number() over (
      partition by pi.trip_id
      order by pi.created_at, pi.id
    ) as rank
  from public.trip_purchase_intents pi
  where pi.status = 'pending'
)
update public.trip_purchase_intents pi
set status = 'expired'
from ranked r
where r.id = pi.id and r.rank > 1;

create unique index if not exists trip_purchase_intents_one_pending_trip_key
  on public.trip_purchase_intents (trip_id)
  where status = 'pending';

-- A scoring-engine upgrade gets a new revision; historical snapshots remain
-- immutable. This also prevents a ts2 worker from colliding with the current
-- ts1 primary key during a rolling deployment.
with bumped as (
  update public.trips t
  set score_revision = t.score_revision + 1
  where exists (
    select 1
    from public.trip_leaderboard_snapshots s
    where s.trip_id = t.id
      and s.revision = t.score_revision
      and s.scoring_engine_version <> 'tee-circle-ts-2'
  )
  returning t.id, t.score_revision
)
insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
select b.id, b.score_revision from bumped b
on conflict (trip_id, revision) do update
  set status = 'pending', available_at = now(), leased_until = null;

comment on column public.trip_hole_scores.strokes is
  'Played strokes only. Penalty strokes are stored separately in penalties and are additive for authoritative gross/net scoring.';
comment on column public.trip_hole_scores.penalties is
  'Penalty strokes added to strokes by the authoritative scoring engine.';

-- Preserve explicit nulls inside structured details (for example
-- details.currentScore = null) while continuing to omit absent envelope
-- fields. The previous recursive jsonb_strip_nulls removed that distinction.
create or replace function tee_internal.api_error(
  p_request_id uuid,
  p_code text,
  p_message text,
  p_retryable boolean default false,
  p_current_revision bigint default null,
  p_details jsonb default null
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'schemaVersion', 1,
    'requestId', p_request_id,
    'error',
      jsonb_build_object(
        'code', p_code,
        'message', p_message,
        'retryable', p_retryable
      )
      || case when p_current_revision is null then '{}'::jsonb
              else jsonb_build_object('currentRevision', p_current_revision) end
      || case when p_details is null then '{}'::jsonb
              else jsonb_build_object('details', p_details) end
  );
$$;

create or replace function tee_internal.current_score_conflict_details_v1(
  p_round_id uuid,
  p_trip_player_id uuid,
  p_hole_number smallint
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'currentScore', (
      select jsonb_build_object(
        'strokes', s.strokes,
        'penalties', s.penalties,
        'revision', s.revision
      )
      from public.trip_hole_scores s
      where s.round_id = p_round_id
        and s.trip_player_id = p_trip_player_id
        and s.hole_number = p_hole_number
    )
  );
$$;

revoke all on function tee_internal.current_score_conflict_details_v1(uuid, uuid, smallint) from public;

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
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if char_length(coalesce(p_device_id, '')) not between 8 and 200 then
    return tee_internal.api_error(v_request_id, 'invalid_device_id', 'A stable device identifier is required.');
  end if;

  select tp.id into v_trip_player_id
  from public.trip_players tp
  join public.trips t on t.id = tp.trip_id
  where tp.trip_id = p_trip_id
    and tp.claimed_user_id = v_user_id
    and tp.rsvp <> 'no'
    and t.status <> 'archived'
  limit 1;
  if not found then
    return tee_internal.api_error(v_request_id, 'roster_claim_required', 'Claim a roster spot before connecting Messages.');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_user_id::text || ':' || p_device_id || ':' || p_trip_id::text, 0)
  );
  update public.extension_sessions
  set revoked_at = now()
  where user_id = v_user_id
    and device_id = p_device_id
    and trip_id = p_trip_id
    and revoked_at is null;

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
        'holeCount', r.holes,
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
                'strokes', s.strokes,
                'penalties', coalesce(s.penalties, 0)
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

create or replace function public.update_trip_player_v1(p_trip_player_id uuid, p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_player public.trip_players%rowtype;
  v_trip public.trips%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  select * into v_player from public.trip_players tp where tp.id = p_trip_player_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_player.trip_id;
  if tee_internal.trip_role(v_player.trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can edit roster details.');
  end if;
  if v_trip.status not in ('draft', 'ready') then
    return tee_internal.api_error(v_request_id, 'roster_locked', 'Roster details are locked after scoring begins.');
  end if;
  if v_player.role = 'captain' and p_input ? 'role' and p_input->>'role' <> 'captain' then
    return tee_internal.api_error(v_request_id, 'captain_role_required', 'Transfer ownership before changing the captain role.');
  end if;

  update public.trip_players tp set
    display_name = case when p_input ? 'displayName' then btrim(p_input->>'displayName') else tp.display_name end,
    role = case when p_input ? 'role' then p_input->>'role' else tp.role end,
    rsvp = case when p_input ? 'rsvp' then p_input->>'rsvp' else tp.rsvp end,
    handicap_snapshot = case
      when p_input ? 'handicap' and p_input->'handicap' = 'null'::jsonb then null
      when p_input ? 'handicap' then (p_input->>'handicap')::numeric
      else tp.handicap_snapshot
    end
  where tp.id = p_trip_player_id
  returning * into v_player;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripPlayerId', v_player.id,
    'displayName', v_player.display_name,
    'role', v_player.role,
    'rsvp', v_player.rsvp,
    'handicapSnapshot', v_player.handicap_snapshot
  ));
exception
  when invalid_text_representation or check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'One or more roster fields are invalid.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'duplicate_player', 'That display name is already on the roster.');
end;
$$;

create or replace function public.set_round_participation_v1(
  p_round_id uuid,
  p_trip_player_id uuid,
  p_course_handicap smallint,
  p_playing_handicap smallint,
  p_status text default 'active'
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
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  select t.* into v_trip
  from public.trips t join public.rounds r on r.trip_id = t.id
  where r.id = p_round_id for update of t;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  if tee_internal.trip_role(v_trip.id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can edit round participation.');
  end if;
  if v_trip.status <> 'draft' then
    return tee_internal.api_error(v_request_id, 'trip_not_editable', 'Round participation can only change in a draft trip.');
  end if;
  if not exists (
    select 1 from public.trip_players tp
    where tp.id = p_trip_player_id and tp.trip_id = v_trip.id
  ) then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;

  insert into public.trip_round_players (
    round_id, trip_player_id, course_handicap, playing_handicap, status
  ) values (
    p_round_id, p_trip_player_id, p_course_handicap, p_playing_handicap, p_status
  )
  on conflict (round_id, trip_player_id) do update set
    course_handicap = excluded.course_handicap,
    playing_handicap = excluded.playing_handicap,
    status = excluded.status;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'roundId', p_round_id,
    'tripPlayerId', p_trip_player_id,
    'status', p_status
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Participation values are invalid.');
end;
$$;

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
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
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
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
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
  select * into v_trip from public.trips t where t.id = p_trip_id;
  if not found or not tee_internal.is_trip_member(p_trip_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if v_trip.status <> 'live' then
    return tee_internal.api_error(v_request_id, 'trip_not_live', 'Live Activities can only follow a live trip.');
  end if;
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

create unique index if not exists rounds_one_live_per_trip_key
  on public.rounds (trip_id)
  where trip_id is not null and trip_round_status = 'live';

-- Draft setup and final archival remain on the legacy status command. Starting
-- or completing competition must use the atomic trip/round commands below.
create or replace function public.set_trip_status_v1(
  p_trip_id uuid,
  p_expected_status text,
  p_new_status text
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
  v_issues jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  if p_expected_status is null or p_new_status is null then
    return tee_internal.api_error(v_request_id, 'invalid_status_transition', 'Trip statuses are required.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can change trip status.');
  end if;
  if v_trip.status is distinct from p_expected_status then
    return tee_internal.api_error(
      v_request_id,
      'status_conflict',
      'The trip status changed on another device.',
      false,
      v_trip.score_revision,
      jsonb_build_object('currentStatus', v_trip.status)
    );
  end if;
  if (p_expected_status = 'ready' and p_new_status = 'live')
     or (p_expected_status = 'live' and p_new_status = 'completed') then
    return tee_internal.api_error(
      v_request_id,
      'atomic_lifecycle_required',
      'Start and advance trips with the atomic lifecycle command.',
      false,
      v_trip.score_revision,
      jsonb_build_object(
        'requiredCommand', case when p_new_status = 'live' then 'start_trip_v1' else 'advance_trip_round_v1' end
      )
    );
  end if;
  if not (
    (p_expected_status = 'draft' and p_new_status = 'ready')
    or (p_expected_status = 'completed' and p_new_status = 'archived')
  ) then
    return tee_internal.api_error(v_request_id, 'invalid_status_transition', 'That trip status transition is not allowed.');
  end if;
  if p_new_status = 'ready' then
    v_issues := tee_internal.trip_readiness_issues(p_trip_id);
    if jsonb_array_length(v_issues) > 0 then
      return tee_internal.api_error(
        v_request_id,
        'trip_not_ready',
        'Complete the trip setup before marking it ready.',
        false,
        v_trip.score_revision,
        v_issues
      );
    end if;
  end if;

  update public.trips set status = p_new_status where id = p_trip_id;
  if p_new_status = 'ready' then
    insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
    values (p_trip_id, v_trip.score_revision)
    on conflict (trip_id, revision) do update
      set status = 'pending', available_at = now(), leased_until = null;
  end if;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'status', p_new_status,
    'scoreRevision', v_trip.score_revision
  ));
end;
$$;

create or replace function public.start_trip_v1(
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
  v_round_id uuid;
  v_revision bigint;
  v_issues jsonb;
  v_purchases_required boolean;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'trip_not_found', 'Trip not found.');
  end if;
  if tee_internal.trip_role(p_trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can start this trip.');
  end if;
  if p_expected_score_revision is not null and v_trip.score_revision <> p_expected_score_revision then
    return tee_internal.api_error(v_request_id, 'score_conflict', 'The trip changed on another device.', false, v_trip.score_revision);
  end if;
  if v_trip.status is distinct from 'ready' then
    return tee_internal.api_error(
      v_request_id,
      'status_conflict',
      'Only a ready trip can start.',
      false,
      v_trip.score_revision,
      jsonb_build_object('currentStatus', v_trip.status)
    );
  end if;
  v_issues := tee_internal.trip_readiness_issues(p_trip_id);
  if jsonb_array_length(v_issues) > 0 then
    return tee_internal.api_error(v_request_id, 'trip_not_ready', 'Complete the trip setup before starting.', false, v_trip.score_revision, v_issues);
  end if;
  if exists (
    select 1 from public.rounds r
    where r.trip_id = p_trip_id
      and r.trip_round_status is distinct from 'scheduled'
  ) then
    return tee_internal.api_error(v_request_id, 'round_state_conflict', 'Every round must be scheduled when a trip starts.', false, v_trip.score_revision);
  end if;
  select coalesce((select enabled from tee_internal.runtime_flags where key = 'purchases_required'), true)
    into v_purchases_required;
  if v_purchases_required and not exists (
    select 1 from public.trip_entitlements te where te.trip_id = p_trip_id
  ) then
    return tee_internal.api_error(v_request_id, 'trip_unlock_required', 'The captain must unlock this trip before scoring starts.');
  end if;
  select r.id into v_round_id
  from public.rounds r
  where r.trip_id = p_trip_id and r.trip_round_status = 'scheduled'
  order by r.trip_order
  limit 1
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_required', 'Add a scheduled round before starting the trip.');
  end if;

  v_revision := v_trip.score_revision + 1;
  update public.rounds
  set trip_round_status = 'live', native_updated_at = now()
  where id = v_round_id;
  update public.trips
  set status = 'live', score_revision = v_revision
  where id = p_trip_id;
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  values (p_trip_id, v_revision)
  on conflict (trip_id, revision) do update
    set status = 'pending', available_at = now(), leased_until = null;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'tripStatus', 'live',
    'currentRoundId', v_round_id,
    'currentRoundStatus', 'live',
    'scoreRevision', v_revision
  ));
end;
$$;

create or replace function public.advance_trip_round_v1(
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
  v_current_order smallint;
  v_current_status text;
  v_next_round_id uuid;
  v_revision bigint;
  v_trip_status text;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
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
  if p_expected_score_revision is not null and v_trip.score_revision <> p_expected_score_revision then
    return tee_internal.api_error(v_request_id, 'score_conflict', 'The trip changed on another device.', false, v_trip.score_revision);
  end if;
  if v_trip.status is distinct from 'live' then
    return tee_internal.api_error(
      v_request_id,
      'status_conflict',
      'Only a live trip can advance rounds.',
      false,
      v_trip.score_revision,
      jsonb_build_object('currentStatus', v_trip.status)
    );
  end if;
  select r.trip_order, r.trip_round_status into v_current_order, v_current_status
  from public.rounds r
  where r.id = p_current_round_id and r.trip_id = p_trip_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  if v_current_status is distinct from 'live' then
    return tee_internal.api_error(
      v_request_id,
      'status_conflict',
      'The current round is not live.',
      false,
      v_trip.score_revision,
      jsonb_build_object('currentStatus', v_current_status)
    );
  end if;
  if exists (
    select 1 from public.rounds r
    where r.trip_id = p_trip_id and r.id <> p_current_round_id and r.trip_round_status = 'live'
  ) then
    return tee_internal.api_error(v_request_id, 'round_state_conflict', 'More than one round is live.', false, v_trip.score_revision);
  end if;
  if exists (
    select 1 from public.rounds r
    where r.trip_id = p_trip_id and r.trip_round_status = 'scheduled' and r.trip_order < v_current_order
  ) then
    return tee_internal.api_error(v_request_id, 'round_state_conflict', 'An earlier round is still scheduled.', false, v_trip.score_revision);
  end if;
  if not coalesce(p_allow_incomplete, false) and exists (
    select 1
    from public.trip_round_players trp
    join public.round_holes rh on rh.round_id = trp.round_id
    left join public.trip_hole_scores s
      on s.round_id = trp.round_id
      and s.trip_player_id = trp.trip_player_id
      and s.hole_number = rh.hole_number
    where trp.round_id = p_current_round_id
      and trp.status = 'active'
      and s.id is null
  ) then
    return tee_internal.api_error(v_request_id, 'scores_incomplete', 'Some active players have missing hole scores.', false, v_trip.score_revision);
  end if;

  select r.id into v_next_round_id
  from public.rounds r
  where r.trip_id = p_trip_id
    and r.trip_round_status = 'scheduled'
    and r.trip_order > v_current_order
  order by r.trip_order
  limit 1
  for update;

  update public.rounds
  set trip_round_status = 'completed', native_updated_at = now()
  where id = p_current_round_id;
  if v_next_round_id is not null then
    update public.rounds
    set trip_round_status = 'live', native_updated_at = now()
    where id = v_next_round_id;
    v_trip_status := 'live';
  else
    if exists (
      select 1 from public.rounds r
      where r.trip_id = p_trip_id
        and r.id <> p_current_round_id
        and r.trip_round_status is distinct from 'completed'
    ) then
      raise exception using errcode = 'P0001', message = 'trip_round_state_invariant';
    end if;
    v_trip_status := 'completed';
  end if;

  v_revision := v_trip.score_revision + 1;
  update public.trips
  set status = v_trip_status, score_revision = v_revision
  where id = p_trip_id;
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  values (p_trip_id, v_revision)
  on conflict (trip_id, revision) do update
    set status = 'pending', available_at = now(), leased_until = null;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'tripStatus', v_trip_status,
    'currentRoundId', p_current_round_id,
    'currentRoundStatus', 'completed',
    'nextRoundId', v_next_round_id,
    'nextRoundStatus', case when v_next_round_id is null then null else 'live' end,
    'scoreRevision', v_revision
  ));
exception
  when sqlstate 'P0001' then
    return tee_internal.api_error(v_request_id, 'round_state_conflict', 'The round schedule is inconsistent.', false, v_trip.score_revision);
end;
$$;

create or replace function public.record_hole_score_v1(
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
  v_trip public.trips%rowtype;
  v_trip_id uuid;
  v_round_status text;
  v_score public.trip_hole_scores%rowtype;
  v_audit public.trip_score_audit%rowtype;
  v_previous_strokes smallint;
  v_previous_penalties smallint;
  v_revision bigint;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Score changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null or p_strokes is null or p_penalties is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Score, penalties, and idempotency key are required.');
  end if;

  select r.trip_id, r.trip_round_status into v_trip_id, v_round_status
  from public.rounds r where r.id = p_round_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  select * into strict v_trip from public.trips t where t.id = v_trip_id for update;
  -- Lifecycle commands lock trip then round. Re-read the round under that same
  -- lock order so a score waiting behind an advance cannot use stale `live`.
  select r.trip_id, r.trip_round_status into v_trip_id, v_round_status
  from public.rounds r
  where r.id = p_round_id and r.trip_id = v_trip.id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  perform 1 from public.trip_players tp
  where tp.id = p_trip_player_id and tp.trip_id = v_trip.id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'forbidden', 'You cannot score for that player.');
  end if;
  if not tee_internal.can_score_player(v_trip.id, p_trip_player_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'forbidden', 'You cannot score for that player.');
  end if;
  if not exists (
    select 1 from public.trip_round_players trp
    where trp.round_id = p_round_id and trp.trip_player_id = p_trip_player_id and trp.status = 'active'
  ) then
    return tee_internal.api_error(v_request_id, 'player_not_active', 'That player is not active in this round.', false, v_trip.score_revision);
  end if;
  if not exists (
    select 1 from public.round_holes rh
    where rh.round_id = p_round_id and rh.hole_number = p_hole_number
  ) then
    return tee_internal.api_error(v_request_id, 'hole_not_found', 'That hole is not part of this round.', false, v_trip.score_revision);
  end if;

  select * into v_audit from public.trip_score_audit a
  where a.actor_user_id = v_user_id and a.idempotency_key = p_idempotency_key;
  if found then
    if v_audit.round_id = p_round_id
       and v_audit.trip_player_id = p_trip_player_id
       and v_audit.hole_number = p_hole_number
       and v_audit.strokes = p_strokes
       and v_audit.penalties = p_penalties then
      return tee_internal.api_success(v_request_id, jsonb_build_object(
        'tripId', v_audit.trip_id,
        'scoreId', v_audit.score_id,
        'acceptedRevision', v_audit.revision,
        'idempotentReplay', true
      ));
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another score.');
  end if;
  if v_trip.status is distinct from 'live'
     or v_round_status is distinct from 'live' then
    return tee_internal.api_error(v_request_id, 'scoring_closed', 'Scoring is only available for the live round.', false, v_trip.score_revision);
  end if;

  -- Only an actor who is still authorized for this locked roster seat may
  -- observe the current revision or target-hole conflict value.
  if p_expected_score_revision is not null and v_trip.score_revision <> p_expected_score_revision then
    return tee_internal.api_error(
      v_request_id,
      'score_conflict',
      'The leaderboard changed on another device.',
      false,
      v_trip.score_revision,
      tee_internal.current_score_conflict_details_v1(p_round_id, p_trip_player_id, p_hole_number)
    );
  end if;

  select * into v_score from public.trip_hole_scores s
  where s.round_id = p_round_id
    and s.trip_player_id = p_trip_player_id
    and s.hole_number = p_hole_number
  for update;
  if found then
    v_previous_strokes := v_score.strokes;
    v_previous_penalties := v_score.penalties;
  end if;

  v_revision := v_trip.score_revision + 1;
  update public.trips set score_revision = v_revision where id = v_trip.id;
  insert into public.trip_hole_scores (
    trip_id, round_id, trip_player_id, hole_number,
    strokes, penalties, recorded_by_user_id, revision, idempotency_key
  ) values (
    v_trip.id, p_round_id, p_trip_player_id, p_hole_number,
    p_strokes, p_penalties, v_user_id, v_revision, p_idempotency_key
  )
  on conflict (round_id, trip_player_id, hole_number) do update set
    strokes = excluded.strokes,
    penalties = excluded.penalties,
    recorded_by_user_id = excluded.recorded_by_user_id,
    revision = excluded.revision,
    idempotency_key = excluded.idempotency_key
  returning * into v_score;

  insert into public.trip_score_audit (
    score_id, trip_id, round_id, trip_player_id, hole_number,
    previous_strokes, strokes, previous_penalties, penalties,
    actor_user_id, revision, idempotency_key
  ) values (
    v_score.id, v_trip.id, p_round_id, p_trip_player_id, p_hole_number,
    v_previous_strokes, p_strokes, v_previous_penalties, p_penalties,
    v_user_id, v_revision, p_idempotency_key
  );
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  values (v_trip.id, v_revision)
  on conflict (trip_id, revision) do update
    set status = 'pending', available_at = now(), leased_until = null;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'scoreId', v_score.id,
    'acceptedRevision', v_revision,
    'idempotentReplay', false,
    'score', jsonb_build_object(
      'roundId', p_round_id,
      'tripPlayerId', p_trip_player_id,
      'holeNumber', p_hole_number,
      'strokes', p_strokes,
      'penalties', p_penalties,
      'grossTotal', p_strokes + p_penalties
    )
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_score', 'Strokes must be 1–30 and penalties 0–30.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'score_write_conflict', 'The score changed while it was being saved. Refresh and retry.', true);
end;
$$;

-- The authenticated client cannot bypass the synchronous score Edge pipeline.
-- Its verified user UUID is supplied only by the service-role endpoint, then
-- the existing command performs the normal seat/scorer authorization checks.
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
begin
  if p_actor_user_id is null
     or not exists (select 1 from auth.users u where u.id = p_actor_user_id) then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'A verified user is required.');
  end if;
  perform set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  return public.record_hole_score_v1(
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

create or replace function public.record_extension_hole_score_service_v1(
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
  v_session public.extension_sessions%rowtype;
  v_trip public.trips%rowtype;
  v_round_trip_id uuid;
  v_round_status text;
  v_score public.trip_hole_scores%rowtype;
  v_audit public.trip_score_audit%rowtype;
  v_previous_strokes smallint;
  v_previous_penalties smallint;
  v_revision bigint;
begin
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Score changes are temporarily unavailable.', true);
  end if;
  if p_idempotency_key is null or p_strokes is null or p_penalties is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Score, penalties, and idempotency key are required.');
  end if;
  select * into v_session from public.extension_sessions s
  where s.token_hash = decode(p_token_hash_hex, 'hex')
    and s.revoked_at is null and s.expires_at > now();
  if not found then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  if p_trip_player_id is distinct from v_session.trip_player_id then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Messages can only score your claimed roster spot.');
  end if;
  select r.trip_id, r.trip_round_status into v_round_trip_id, v_round_status
  from public.rounds r where r.id = p_round_id;
  if not found or v_round_trip_id is distinct from v_session.trip_id then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  select * into strict v_trip from public.trips t where t.id = v_round_trip_id for update;
  select r.trip_id, r.trip_round_status into v_round_trip_id, v_round_status
  from public.rounds r
  where r.id = p_round_id and r.trip_id = v_trip.id
  for update;
  if not found or v_round_trip_id is distinct from v_session.trip_id then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  perform 1 from public.trip_players tp
  where tp.id = v_session.trip_player_id
    and tp.trip_id = v_session.trip_id
    and tp.claimed_user_id = v_session.user_id
    and tp.rsvp <> 'no'
  for update;
  if not found then
    update public.extension_sessions set revoked_at = now() where id = v_session.id;
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  -- Revalidate and lock the credential after trip and seat, matching claim
  -- revocation's lock order and preventing a revoked token from committing.
  select * into v_session from public.extension_sessions s
  where s.id = v_session.id
    and s.token_hash = decode(p_token_hash_hex, 'hex')
    and s.revoked_at is null and s.expires_at > now()
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  end if;
  if not exists (
    select 1 from public.trip_round_players trp
    where trp.round_id = p_round_id and trp.trip_player_id = p_trip_player_id and trp.status = 'active'
  ) then
    return tee_internal.api_error(v_request_id, 'player_not_active', 'You are not active in this round.', false, v_trip.score_revision);
  end if;
  if not exists (
    select 1 from public.round_holes rh where rh.round_id = p_round_id and rh.hole_number = p_hole_number
  ) then
    return tee_internal.api_error(v_request_id, 'hole_not_found', 'That hole is not part of this round.', false, v_trip.score_revision);
  end if;

  select * into v_audit from public.trip_score_audit a
  where a.actor_user_id = v_session.user_id and a.idempotency_key = p_idempotency_key;
  if found then
    if v_audit.round_id = p_round_id
       and v_audit.trip_player_id = p_trip_player_id
       and v_audit.hole_number = p_hole_number
       and v_audit.strokes = p_strokes
       and v_audit.penalties = p_penalties then
      return tee_internal.api_success(v_request_id, jsonb_build_object(
        'tripId', v_audit.trip_id,
        'scoreId', v_audit.score_id,
        'acceptedRevision', v_audit.revision,
        'idempotentReplay', true
      ));
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another score.');
  end if;
  if v_trip.status is distinct from 'live'
     or v_round_status is distinct from 'live' then
    return tee_internal.api_error(v_request_id, 'scoring_closed', 'Scoring is only available for the live round.', false, v_trip.score_revision);
  end if;
  if p_expected_score_revision is not null and v_trip.score_revision <> p_expected_score_revision then
    return tee_internal.api_error(
      v_request_id,
      'score_conflict',
      'The leaderboard changed on another device.',
      false,
      v_trip.score_revision,
      tee_internal.current_score_conflict_details_v1(p_round_id, p_trip_player_id, p_hole_number)
    );
  end if;

  select * into v_score from public.trip_hole_scores s
  where s.round_id = p_round_id and s.trip_player_id = p_trip_player_id and s.hole_number = p_hole_number
  for update;
  if found then
    v_previous_strokes := v_score.strokes;
    v_previous_penalties := v_score.penalties;
  end if;

  v_revision := v_trip.score_revision + 1;
  update public.trips set score_revision = v_revision where id = v_trip.id;
  insert into public.trip_hole_scores (
    trip_id, round_id, trip_player_id, hole_number, strokes, penalties,
    recorded_by_user_id, revision, idempotency_key
  ) values (
    v_trip.id, p_round_id, p_trip_player_id, p_hole_number, p_strokes, p_penalties,
    v_session.user_id, v_revision, p_idempotency_key
  )
  on conflict (round_id, trip_player_id, hole_number) do update set
    strokes = excluded.strokes,
    penalties = excluded.penalties,
    recorded_by_user_id = excluded.recorded_by_user_id,
    revision = excluded.revision,
    idempotency_key = excluded.idempotency_key
  returning * into v_score;
  insert into public.trip_score_audit (
    score_id, trip_id, round_id, trip_player_id, hole_number,
    previous_strokes, strokes, previous_penalties, penalties,
    actor_user_id, revision, idempotency_key
  ) values (
    v_score.id, v_trip.id, p_round_id, p_trip_player_id, p_hole_number,
    v_previous_strokes, p_strokes, v_previous_penalties, p_penalties,
    v_session.user_id, v_revision, p_idempotency_key
  );
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  values (v_trip.id, v_revision)
  on conflict (trip_id, revision) do update
    set status = 'pending', available_at = now(), leased_until = null;
  update public.extension_sessions set last_used_at = now() where id = v_session.id;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'scoreId', v_score.id,
    'acceptedRevision', v_revision,
    'idempotentReplay', false,
    'score', jsonb_build_object(
      'roundId', p_round_id,
      'tripPlayerId', p_trip_player_id,
      'holeNumber', p_hole_number,
      'strokes', p_strokes,
      'penalties', p_penalties,
      'grossTotal', p_strokes + p_penalties
    )
  ));
exception
  when invalid_parameter_value or invalid_text_representation then
    return tee_internal.api_error(v_request_id, 'extension_session_expired', 'Open TeeCircle to reconnect Messages.');
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_score', 'Strokes must be 1–30 and penalties 0–30.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'score_write_conflict', 'The score changed while it was being saved. Refresh and retry.', true);
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
  v_snapshot public.trip_leaderboard_snapshots%rowtype;
  v_replay boolean := false;
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
    return tee_internal.api_error(
      v_request_id,
      'unsupported_scoring_engine',
      'Only the current scoring engine may persist a canonical snapshot.',
      false,
      v_trip.score_revision,
      jsonb_build_object('requiredEngine', 'tee-circle-ts-2')
    );
  end if;

  insert into public.trip_leaderboard_snapshots (
    trip_id, revision, scoring_engine_version, payload, is_final
  ) values (
    p_trip_id, p_revision, p_scoring_engine_version, p_payload,
    v_trip.status = 'completed'
  )
  on conflict (trip_id, revision) do nothing;
  if found then
    v_replay := false;
  else
    v_replay := true;
  end if;

  select * into v_snapshot
  from public.trip_leaderboard_snapshots s
  where s.trip_id = p_trip_id and s.revision = p_revision;
  if not found then
    return tee_internal.api_error(v_request_id, 'snapshot_persist_failed', 'The canonical snapshot was not persisted.', true, v_trip.score_revision);
  end if;
  if v_snapshot.scoring_engine_version is distinct from p_scoring_engine_version then
    return tee_internal.api_error(
      v_request_id,
      'snapshot_engine_conflict',
      'This revision was already computed by another scoring engine.',
      false,
      v_trip.score_revision,
      jsonb_build_object('currentEngine', v_snapshot.scoring_engine_version)
    );
  end if;

  update tee_internal.leaderboard_recompute_jobs set
    status = 'completed', completed_at = now(), leased_until = null
  where trip_id = p_trip_id and revision <= p_revision and status <> 'completed';
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'revision', p_revision,
    'isFinal', v_snapshot.is_final,
    'idempotentReplay', v_replay,
    'scoringEngineVersion', v_snapshot.scoring_engine_version,
    'payload', v_snapshot.payload,
    'computedAt', v_snapshot.computed_at
  ));
exception
  when invalid_text_representation then
    return tee_internal.api_error(v_request_id, 'invalid_snapshot', 'Snapshot identity or schema version is invalid.');
end;
$$;

create or replace function public.get_latest_activity_snapshots_service_v1(
  p_trip_ids uuid[],
  p_revision bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_snapshots jsonb;
begin
  if p_trip_ids is null
     or coalesce(array_length(p_trip_ids, 1), 0) not between 1 and 100 then
    return tee_internal.api_error(v_request_id, 'invalid_trip_ids', 'Provide between 1 and 100 trip IDs.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'tripId', latest.trip_id,
    'revision', latest.revision,
    'payload', latest.payload,
    'computedAt', latest.computed_at
  ) order by latest.trip_id), '[]'::jsonb)
  into v_snapshots
  from (
    select distinct on (s.trip_id)
      s.trip_id, s.revision, s.payload, s.computed_at
    from public.trip_leaderboard_snapshots s
    where s.trip_id = any(p_trip_ids)
      and (p_revision is null or s.revision = p_revision)
    order by s.trip_id, s.revision desc
  ) latest;
  return tee_internal.api_success(v_request_id, jsonb_build_object('snapshots', v_snapshots));
end;
$$;

create or replace function public.get_runtime_flag_service_v1(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_enabled boolean;
begin
  select rf.enabled into v_enabled
  from tee_internal.runtime_flags rf where rf.key = p_key;
  if not found then
    return tee_internal.api_error(v_request_id, 'runtime_flag_not_found', 'Runtime flag not found.');
  end if;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'key', p_key,
    'enabled', v_enabled
  ));
end;
$$;

-- Safe for pg_cron or an operator to invoke without any HTTP/service secret:
-- it only restores missing outbox rows. The Edge reconciler remains the worker
-- that leases these rows and computes authoritative snapshots.
create or replace function tee_internal.enqueue_missing_trip_snapshot_jobs_v1()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_count integer;
begin
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  select t.id, t.score_revision
  from public.trips t
  where t.status in ('ready', 'live', 'completed')
    and not exists (
      select 1 from public.trip_leaderboard_snapshots s
      where s.trip_id = t.id and s.revision = t.score_revision
    )
  on conflict (trip_id, revision) do update set
    status = 'pending',
    available_at = now(),
    leased_until = null,
    last_error = null
  where tee_internal.leaderboard_recompute_jobs.status <> 'processing';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.enqueue_missing_trip_snapshot_jobs_service_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_count integer;
begin
  v_count := tee_internal.enqueue_missing_trip_snapshot_jobs_v1();
  return tee_internal.api_success(v_request_id, jsonb_build_object('enqueued', v_count));
end;
$$;

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
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;
  select * into v_trip from public.trips t where t.id = p_trip_id;
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
  if not exists (
    select 1 from public.trip_leaderboard_snapshots s
    where s.trip_id = p_trip_id and s.revision = v_trip.score_revision
  ) then
    return tee_internal.api_error(v_request_id, 'leaderboard_updating', 'The initial standings are still being prepared.', true, v_trip.score_revision);
  end if;

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.trip_invites (
    trip_id, token_hash, created_by, expires_at, max_uses
  ) values (
    p_trip_id, extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), v_user_id, p_expires_at, p_max_uses
  ) returning id into v_invite_id;

  v_response := tee_internal.api_success(v_request_id, jsonb_build_object(
    'inviteId', v_invite_id,
    'inviteToken', v_token,
    'url', 'https://teecircle.app/t/' || v_token,
    'expiresAt', p_expires_at
  ));
  insert into tee_internal.command_idempotency
    (user_id, idempotency_key, operation, request_hash, response)
  values (v_user_id, p_idempotency_key, 'create_trip_invite_v1', v_hash, v_response);
  return v_response;
exception
  when check_violation then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Invite settings are invalid.');
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
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  perform 1 from public.trips t where t.id = p_trip_id and t.owner_id = v_user_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can transfer this trip.');
  end if;
  select tp.claimed_user_id into v_new_user_id from public.trip_players tp
  where tp.id = p_new_owner_trip_player_id
    and tp.trip_id = p_trip_id
    and tp.claimed_user_id is not null
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'claimed_player_required', 'Transfer ownership to a claimed roster player.');
  end if;
  if v_new_user_id = v_user_id then
    return tee_internal.api_error(v_request_id, 'owner_unchanged', 'Choose another claimed roster player.');
  end if;
  select tp.id into v_old_player_id from public.trip_players tp
  where tp.trip_id = p_trip_id and tp.claimed_user_id = v_user_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'captain_seat_not_found', 'The current captain roster seat is unavailable.');
  end if;

  -- Never orphan a StoreKit transaction already in flight. Ownership can move
  -- after that intent is verified, explicitly cancelled, or naturally expires.
  update public.trip_purchase_intents
  set status = 'expired'
  where trip_id = p_trip_id and status = 'pending' and expires_at <= now();
  if exists (
    select 1 from public.trip_purchase_intents pi
    where pi.trip_id = p_trip_id and pi.status = 'pending'
  ) then
    return tee_internal.api_error(
      v_request_id,
      'purchase_pending',
      'Finish or cancel the pending trip purchase before transferring ownership.',
      false,
      null,
      (
        select jsonb_build_object(
          'purchaseIntentId', pi.id,
          'expiresAt', pi.expires_at
        )
        from public.trip_purchase_intents pi
        where pi.trip_id = p_trip_id and pi.status = 'pending'
        order by pi.created_at
        limit 1
      )
    );
  end if;
  update public.trip_players set role = 'player' where id = v_old_player_id;
  update public.trip_players set role = 'captain' where id = p_new_owner_trip_player_id;
  update public.trips set owner_id = v_new_user_id where id = p_trip_id;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'newOwnerTripPlayerId', p_new_owner_trip_player_id,
    'newOwnerUserId', v_new_user_id
  ));
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
  v_reused boolean := false;
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
    if v_existing.operation = 'create_trip_purchase_intent_v1' and v_existing.request_hash = v_hash then
      return v_existing.response;
    end if;
    return tee_internal.api_error(v_request_id, 'idempotency_key_reused', 'That idempotency key was already used for another request.');
  end if;

  -- The trip row serializes different idempotency keys for this purchase.
  perform 1 from public.trips t
  where t.id = p_trip_id and t.owner_id = v_user_id
  for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the trip captain can purchase the unlock.');
  end if;
  if exists (select 1 from public.trip_entitlements te where te.trip_id = p_trip_id) then
    return tee_internal.api_error(v_request_id, 'trip_already_unlocked', 'This trip is already unlocked.');
  end if;

  update public.trip_purchase_intents set status = 'expired'
  where trip_id = p_trip_id
    and status = 'pending'
    and (expires_at <= now() or user_id <> v_user_id);
  select * into v_intent from public.trip_purchase_intents pi
  where pi.trip_id = p_trip_id and pi.status = 'pending'
  order by pi.created_at, pi.id
  limit 1
  for update;
  if found then
    v_reused := true;
  else
    insert into public.trip_purchase_intents (trip_id, user_id)
    values (p_trip_id, v_user_id) returning * into v_intent;
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

revoke all on function public.claim_trip_player_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function public.set_trip_round_status_v1(uuid, text, text, boolean) from public, anon, authenticated;
revoke all on function public.record_hole_score_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint)
  from public, anon, authenticated, service_role;

revoke all on function public.start_trip_v1(uuid, bigint) from public;
revoke all on function public.advance_trip_round_v1(uuid, uuid, bigint, boolean) from public;
revoke all on function public.record_authenticated_hole_score_service_v1(uuid, uuid, uuid, smallint, smallint, smallint, uuid, bigint) from public;
revoke all on function public.get_latest_activity_snapshots_service_v1(uuid[], bigint) from public;
revoke all on function public.get_runtime_flag_service_v1(text) from public;
revoke all on function tee_internal.enqueue_missing_trip_snapshot_jobs_v1() from public;
revoke all on function public.enqueue_missing_trip_snapshot_jobs_service_v1() from public;

grant execute on function public.start_trip_v1(uuid, bigint) to authenticated;
grant execute on function public.advance_trip_round_v1(uuid, uuid, bigint, boolean) to authenticated;
grant execute on function public.record_authenticated_hole_score_service_v1(uuid, uuid, uuid, smallint, smallint, smallint, uuid, bigint) to service_role;
grant execute on function public.get_latest_activity_snapshots_service_v1(uuid[], bigint) to service_role;
grant execute on function public.get_runtime_flag_service_v1(text) to service_role;
grant execute on function tee_internal.enqueue_missing_trip_snapshot_jobs_v1() to service_role;
grant execute on function public.enqueue_missing_trip_snapshot_jobs_service_v1() to service_role;
