set lock_timeout = '10s';
set statement_timeout = '5min';

-- Roster claiming, lifecycle transitions, and the atomic score command.


create or replace function tee_internal.trip_readiness_issues(p_trip_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with trip as (
    select * from public.trips where id = p_trip_id
  ), issues as (
    select 'round_required'::text as code
    where not exists (select 1 from public.rounds r where r.trip_id = p_trip_id)
    union all
    select 'two_players_required'
    where (select count(*) from public.trip_players tp where tp.trip_id = p_trip_id and tp.rsvp <> 'no') < 2
    union all
    select 'round_players_incomplete'
    where exists (
      select 1 from public.rounds r
      where r.trip_id = p_trip_id
        and (select count(*) from public.trip_round_players trp where trp.round_id = r.id and trp.status = 'active') < 2
    )
    union all
    select 'course_card_incomplete'
    where exists (
      select 1 from public.rounds r
      where r.trip_id = p_trip_id
        and (select count(*) from public.round_holes rh where rh.round_id = r.id) <> coalesce(r.holes, 18)
    )
    union all
    select 'stroke_indexes_required'
    where exists (select 1 from trip t where t.scoring_mode = 'net')
      and exists (
        select 1 from public.rounds r
        where r.trip_id = p_trip_id
          and exists (
            select 1 from public.round_holes rh
            where rh.round_id = r.id and rh.stroke_index is null
          )
      )
    union all
    select 'handicaps_required'
    where exists (select 1 from trip t where t.scoring_mode = 'net')
      and exists (
        select 1
        from public.trip_round_players trp
        join public.rounds r on r.id = trp.round_id
        where r.trip_id = p_trip_id and trp.status = 'active'
          and trp.playing_handicap is null
      )
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', code)), '[]'::jsonb)
  from issues;
$$;

revoke all on function tee_internal.trip_readiness_issues(uuid) from public;
grant execute on function tee_internal.trip_readiness_issues(uuid) to authenticated, service_role;

create or replace function public.claim_trip_player_v1(p_trip_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
  v_player public.trip_players%rowtype;
  v_trip public.trips%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  -- Every score/claim mutation locks trip then roster seat. Keeping one lock
  -- order prevents a captain revocation racing an accepted score write.
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
  if v_trip.status in ('completed', 'archived') then
    return tee_internal.api_error(v_request_id, 'claiming_closed', 'Roster claiming is closed for this trip.');
  end if;
  if v_player.claimed_user_id = v_user_id then
    return tee_internal.api_success(v_request_id, jsonb_build_object(
      'tripId', v_player.trip_id, 'tripPlayerId', v_player.id, 'claimed', true
    ));
  end if;
  if v_player.claimed_user_id is not null then
    return tee_internal.api_error(v_request_id, 'seat_already_claimed', 'That roster spot has already been claimed.');
  end if;
  if exists (
    select 1 from public.trip_players tp
    where tp.trip_id = v_player.trip_id and tp.claimed_user_id = v_user_id
  ) then
    return tee_internal.api_error(v_request_id, 'user_already_claimed', 'You already claimed a roster spot on this trip.');
  end if;
  update public.trip_players
  set claimed_user_id = v_user_id, rsvp = 'yes'
  where id = v_player.id
  returning * into v_player;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_player.trip_id,
    'tripPlayerId', v_player.id,
    'displayName', v_player.display_name,
    'claimed', true
  ));
exception
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'claim_conflict', 'The roster changed while you were claiming. Refresh and try again.', true);
end;
$$;

create or replace function public.release_trip_player_claim_v1(p_trip_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
  v_claimed_user_id uuid;
  v_player public.trip_players%rowtype;
  v_trip public.trips%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  -- Match score writes: lock the trip before the roster seat so a revocation
  -- cannot interleave with authorization and score persistence.
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
  v_claimed_user_id := v_player.claimed_user_id;
  if v_player.role = 'captain' then
    return tee_internal.api_error(v_request_id, 'captain_claim_required', 'Transfer trip ownership before releasing the captain seat.');
  end if;
  if v_player.claimed_user_id is distinct from v_user_id
     and tee_internal.trip_role(v_player.trip_id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only this player or the captain can release the claim.');
  end if;
  if v_trip.status = 'archived' then
    return tee_internal.api_error(v_request_id, 'trip_archived', 'Archived trips cannot change roster claims.');
  end if;
  update public.trip_players set claimed_user_id = null where id = v_player.id;
  update public.extension_sessions set revoked_at = now()
  where trip_player_id = v_player.id and revoked_at is null;
  update public.live_activity_subscriptions set ended_at = coalesce(ended_at, now())
  where trip_id = v_player.trip_id
    and user_id = v_claimed_user_id
    and ended_at is null;
  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_player.trip_id, 'tripPlayerId', v_player.id, 'claimed', false
  ));
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
  v_next_revision bigint;
  v_purchases_required boolean;
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
      v_request_id, 'status_conflict', 'The trip status changed on another device.', false,
      v_trip.score_revision, jsonb_build_object('currentStatus', v_trip.status)
    );
  end if;
  if not (
    (p_expected_status = 'draft' and p_new_status = 'ready')
    or (p_expected_status = 'ready' and p_new_status = 'live')
    or (p_expected_status = 'live' and p_new_status = 'completed')
    or (p_expected_status = 'completed' and p_new_status = 'archived')
  ) then
    return tee_internal.api_error(v_request_id, 'invalid_status_transition', 'That trip status transition is not allowed.');
  end if;

  if p_new_status = 'ready' then
    v_issues := tee_internal.trip_readiness_issues(p_trip_id);
    if jsonb_array_length(v_issues) > 0 then
      return tee_internal.api_error(v_request_id, 'trip_not_ready', 'Complete the trip setup before marking it ready.', false, v_trip.score_revision, v_issues);
    end if;
  end if;

  if p_new_status = 'live' then
    select coalesce((select enabled from tee_internal.runtime_flags where key = 'purchases_required'), true)
      into v_purchases_required;
    if v_purchases_required and not exists (
      select 1 from public.trip_entitlements te where te.trip_id = p_trip_id
    ) then
      return tee_internal.api_error(v_request_id, 'trip_unlock_required', 'The captain must unlock this trip before scoring starts.');
    end if;
  end if;

  if p_new_status = 'completed' and exists (
    select 1 from public.rounds r
    where r.trip_id = p_trip_id
      and r.trip_round_status is distinct from 'completed'
  ) then
    return tee_internal.api_error(v_request_id, 'rounds_incomplete', 'Complete every round before completing the trip.');
  end if;

  if p_new_status in ('live', 'completed') then
    v_next_revision := v_trip.score_revision + 1;
    update public.trips set status = p_new_status, score_revision = v_next_revision where id = p_trip_id;
    insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
    values (p_trip_id, v_next_revision)
    on conflict (trip_id, revision) do update
      set status = 'pending', available_at = now(), leased_until = null;
  else
    v_next_revision := v_trip.score_revision;
    update public.trips set status = p_new_status where id = p_trip_id;
    if p_new_status = 'ready' then
      insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
      values (p_trip_id, v_next_revision)
      on conflict (trip_id, revision) do update
        set status = 'pending', available_at = now(), leased_until = null;
    end if;
  end if;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', p_trip_id,
    'status', p_new_status,
    'scoreRevision', v_next_revision
  ));
end;
$$;

create or replace function public.set_trip_round_status_v1(
  p_round_id uuid,
  p_expected_status text,
  p_new_status text,
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
  v_trip_id uuid;
  v_current_status text;
  v_revision bigint;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if p_expected_status is null or p_new_status is null then
    return tee_internal.api_error(v_request_id, 'invalid_status_transition', 'Round statuses are required.');
  end if;
  if p_allow_incomplete is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'allowIncomplete must be true or false.');
  end if;
  select r.trip_id, r.trip_round_status into v_trip_id, v_current_status
  from public.rounds r where r.id = p_round_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  select * into strict v_trip from public.trips t where t.id = v_trip_id for update;
  if tee_internal.trip_role(v_trip.id, v_user_id) is distinct from 'captain' then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the captain can change round status.');
  end if;
  if v_current_status is distinct from p_expected_status then
    return tee_internal.api_error(v_request_id, 'status_conflict', 'The round status changed on another device.', false, v_trip.score_revision, jsonb_build_object('currentStatus', v_current_status));
  end if;
  if not (
    (p_expected_status = 'scheduled' and p_new_status = 'live')
    or (p_expected_status = 'live' and p_new_status = 'completed')
  ) then
    return tee_internal.api_error(v_request_id, 'invalid_status_transition', 'That round status transition is not allowed.');
  end if;
  if v_trip.status is distinct from 'live' then
    return tee_internal.api_error(v_request_id, 'trip_not_live', 'The trip must be live before changing round status.', false, v_trip.score_revision);
  end if;
  if p_new_status = 'live' and exists (
    select 1 from public.rounds r
    where r.trip_id = v_trip.id and r.id <> p_round_id and r.trip_round_status = 'live'
  ) then
    return tee_internal.api_error(v_request_id, 'another_round_live', 'Complete the current live round first.');
  end if;
  if p_new_status = 'completed' and not coalesce(p_allow_incomplete, false) and exists (
    select 1
    from public.trip_round_players trp
    join public.round_holes rh on rh.round_id = trp.round_id
    left join public.trip_hole_scores s
      on s.round_id = trp.round_id
      and s.trip_player_id = trp.trip_player_id
      and s.hole_number = rh.hole_number
    where trp.round_id = p_round_id and trp.status = 'active' and s.id is null
  ) then
    return tee_internal.api_error(v_request_id, 'scores_incomplete', 'Some active players have missing hole scores.');
  end if;

  update public.rounds
  set trip_round_status = p_new_status, native_updated_at = now()
  where id = p_round_id;
  update public.trips set score_revision = score_revision + 1
  where id = v_trip.id returning score_revision into v_revision;
  insert into tee_internal.leaderboard_recompute_jobs (trip_id, revision)
  values (v_trip.id, v_revision)
  on conflict (trip_id, revision) do update
    set status = 'pending', available_at = now(), leased_until = null;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_trip.id,
    'roundId', p_round_id,
    'status', p_new_status,
    'scoreRevision', v_revision
  ));
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
  if p_idempotency_key is null or p_penalties is null then
    return tee_internal.api_error(v_request_id, 'invalid_request', 'Score, penalties, and idempotency key are required.');
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

  select r.trip_id, r.trip_round_status into v_trip_id, v_round_status
  from public.rounds r where r.id = p_round_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'round_not_found', 'Round not found.');
  end if;
  select * into strict v_trip from public.trips t where t.id = v_trip_id for update;
  if p_expected_score_revision is not null and v_trip.score_revision <> p_expected_score_revision then
    return tee_internal.api_error(
      v_request_id, 'score_conflict', 'The leaderboard changed on another device.', false,
      v_trip.score_revision
    );
  end if;
  if v_trip.status is distinct from 'live'
     or v_round_status is distinct from 'live' then
    return tee_internal.api_error(v_request_id, 'scoring_closed', 'Scoring is only available for the live round.', false, v_trip.score_revision);
  end if;
  if not tee_internal.can_score_player(v_trip.id, p_trip_player_id, v_user_id) then
    return tee_internal.api_error(v_request_id, 'forbidden', 'You cannot score for that player.', false, v_trip.score_revision);
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
      'penalties', p_penalties
    )
  ));
exception
  when check_violation or not_null_violation then
    return tee_internal.api_error(v_request_id, 'invalid_score', 'Strokes must be 1–30 and penalties 0–30.');
  when unique_violation then
    return tee_internal.api_error(v_request_id, 'score_write_conflict', 'The score changed while it was being saved. Refresh and retry.', true);
end;
$$;

revoke all on function public.claim_trip_player_v1(uuid) from public;
revoke all on function public.release_trip_player_claim_v1(uuid) from public;
revoke all on function public.update_trip_player_v1(uuid, jsonb) from public;
revoke all on function public.set_trip_status_v1(uuid, text, text) from public;
revoke all on function public.set_trip_round_status_v1(uuid, text, text, boolean) from public;
revoke all on function public.record_hole_score_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint) from public;

grant execute on function public.claim_trip_player_v1(uuid) to authenticated;
grant execute on function public.release_trip_player_claim_v1(uuid) to authenticated;
grant execute on function public.update_trip_player_v1(uuid, jsonb) to authenticated;
grant execute on function public.set_trip_status_v1(uuid, text, text) to authenticated;
grant execute on function public.set_trip_round_status_v1(uuid, text, text, boolean) to authenticated;
grant execute on function public.record_hole_score_v1(uuid, uuid, smallint, smallint, smallint, uuid, bigint) to authenticated;
