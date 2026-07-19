set lock_timeout = '10s';
set statement_timeout = '5min';

-- Bind client-visible authorization helpers to the authenticated JWT and keep
-- roster account identifiers behind versioned server DTOs.


-- The original helpers accept an explicit user id because server commands
-- need to authorize actors after locking their resources. They are not client
-- RPCs: an authenticated caller could otherwise ask the helper to evaluate a
-- different user's membership or role. Keep those existing signatures
-- available only to trusted server code and add separately named, auth-bound
-- wrappers for RLS below. (The legacy defaults remain on the private
-- signatures because PostgreSQL cannot remove them while dependants exist.)

revoke all on function tee_internal.is_trip_member(uuid, uuid)
  from public, anon, authenticated;
revoke all on function tee_internal.trip_role(uuid, uuid)
  from public, anon, authenticated;
revoke all on function tee_internal.can_manage_trip(uuid, uuid)
  from public, anon, authenticated;
revoke all on function tee_internal.can_score_player(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function tee_internal.is_trip_member(uuid, uuid)
  to service_role;
grant execute on function tee_internal.trip_role(uuid, uuid)
  to service_role;
grant execute on function tee_internal.can_manage_trip(uuid, uuid)
  to service_role;
grant execute on function tee_internal.can_score_player(uuid, uuid, uuid)
  to service_role;

create or replace function tee_internal.current_user_is_trip_member(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, auth, tee_internal
as $$
  select tee_internal.is_trip_member(p_trip_id, auth.uid());
$$;

create or replace function tee_internal.current_user_trip_role(p_trip_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, auth, tee_internal
as $$
  select tee_internal.trip_role(p_trip_id, auth.uid());
$$;

create or replace function tee_internal.current_user_can_manage_trip(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, auth, tee_internal
as $$
  select tee_internal.can_manage_trip(p_trip_id, auth.uid());
$$;

create or replace function tee_internal.current_user_can_score_player(
  p_trip_id uuid,
  p_trip_player_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, auth, tee_internal
as $$
  select tee_internal.can_score_player(
    p_trip_id,
    p_trip_player_id,
    auth.uid()
  );
$$;

revoke all on function tee_internal.current_user_is_trip_member(uuid)
  from public, anon;
revoke all on function tee_internal.current_user_trip_role(uuid)
  from public, anon;
revoke all on function tee_internal.current_user_can_manage_trip(uuid)
  from public, anon;
revoke all on function tee_internal.current_user_can_score_player(uuid, uuid)
  from public, anon;
grant execute on function tee_internal.current_user_is_trip_member(uuid)
  to authenticated, service_role;
grant execute on function tee_internal.current_user_trip_role(uuid)
  to authenticated, service_role;
grant execute on function tee_internal.current_user_can_manage_trip(uuid)
  to authenticated, service_role;
grant execute on function tee_internal.current_user_can_score_player(uuid, uuid)
  to authenticated, service_role;

-- Rebind every member-read policy to the auth-bound wrapper. Policies created
-- earlier resolved the defaulted explicit-user helper OID.
drop policy if exists "Trip members can read trips" on public.trips;
create policy "Trip members can read trips"
on public.trips for select to authenticated
using (tee_internal.current_user_is_trip_member(id));

drop policy if exists "Trip members can read roster" on public.trip_players;
create policy "Trip members can read roster"
on public.trip_players for select to authenticated
using (tee_internal.current_user_is_trip_member(trip_id));

drop policy if exists "Trip members can read round holes" on public.round_holes;
create policy "Trip members can read round holes"
on public.round_holes for select to authenticated
using (
  exists (
    select 1
    from public.rounds r
    where r.id = round_holes.round_id
      and r.trip_id is not null
      and tee_internal.current_user_is_trip_member(r.trip_id)
  )
);

drop policy if exists "Trip members can read round roster" on public.trip_round_players;
create policy "Trip members can read round roster"
on public.trip_round_players for select to authenticated
using (
  exists (
    select 1
    from public.trip_players tp
    where tp.id = trip_round_players.trip_player_id
      and tee_internal.current_user_is_trip_member(tp.trip_id)
  )
);

drop policy if exists "Trip members can read scores" on public.trip_hole_scores;
create policy "Trip members can read scores"
on public.trip_hole_scores for select to authenticated
using (tee_internal.current_user_is_trip_member(trip_id));

drop policy if exists "Trip members can read score audit" on public.trip_score_audit;
create policy "Trip members can read score audit"
on public.trip_score_audit for select to authenticated
using (tee_internal.current_user_is_trip_member(trip_id));

drop policy if exists "Trip members can read snapshots" on public.trip_leaderboard_snapshots;
create policy "Trip members can read snapshots"
on public.trip_leaderboard_snapshots for select to authenticated
using (tee_internal.current_user_is_trip_member(trip_id));

drop policy if exists "Trip members can view native rounds" on public.rounds;
create policy "Trip members can view native rounds"
on public.rounds for select to authenticated
using (
  trip_id is not null
  and tee_internal.current_user_is_trip_member(trip_id)
);

-- RLS decides which roster rows a trip member may read. Column privileges
-- independently prevent the raw account binding from crossing the table API;
-- get_trip_bootstrap_v1 continues to expose only `claimed` and `isCurrentUser`.
revoke select on table public.trip_players from public, anon, authenticated;
grant select (
  id,
  trip_id,
  display_name,
  role,
  rsvp,
  handicap_snapshot,
  created_at,
  updated_at
) on table public.trip_players to authenticated;

comment on column public.trip_players.claimed_user_id is
  'Private roster-seat binding. Exposed to clients only as sanitized bootstrap booleans.';
