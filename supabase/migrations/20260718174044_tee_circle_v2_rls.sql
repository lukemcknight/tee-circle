set lock_timeout = '10s';
set statement_timeout = '5min';

-- TeeCircle 2.0 RLS. New native tables are directly readable only where
-- appropriate and writable only through hardened SECURITY DEFINER commands.


create or replace function tee_internal.is_trip_member(p_trip_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_user_id is not null and exists (
    select 1
    from public.trips t
    where t.id = p_trip_id
      and (
        t.owner_id = p_user_id
        or exists (
          select 1
          from public.trip_players tp
          where tp.trip_id = t.id
            and tp.claimed_user_id = p_user_id
            and tp.rsvp <> 'no'
        )
      )
  );
$$;

create or replace function tee_internal.trip_role(p_trip_id uuid, p_user_id uuid default auth.uid())
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when exists (
      select 1 from public.trips t
      where t.id = p_trip_id and t.owner_id = p_user_id
    ) then 'captain'
    else (
      select tp.role
      from public.trip_players tp
      where tp.trip_id = p_trip_id
        and tp.claimed_user_id = p_user_id
        and tp.rsvp <> 'no'
      limit 1
    )
  end;
$$;

create or replace function tee_internal.can_manage_trip(p_trip_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(tee_internal.trip_role(p_trip_id, p_user_id) in ('captain', 'scorer'), false);
$$;

create or replace function tee_internal.can_score_player(
  p_trip_id uuid,
  p_trip_player_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_user_id is not null and (
    tee_internal.can_manage_trip(p_trip_id, p_user_id)
    or exists (
      select 1 from public.trip_players tp
      where tp.id = p_trip_player_id
        and tp.trip_id = p_trip_id
        and tp.claimed_user_id = p_user_id
        and tp.rsvp <> 'no'
    )
  );
$$;

revoke all on function tee_internal.is_trip_member(uuid, uuid) from public;
revoke all on function tee_internal.trip_role(uuid, uuid) from public;
revoke all on function tee_internal.can_manage_trip(uuid, uuid) from public;
revoke all on function tee_internal.can_score_player(uuid, uuid, uuid) from public;
grant usage on schema tee_internal to authenticated, service_role;
grant execute on function tee_internal.is_trip_member(uuid, uuid) to authenticated, service_role;
grant execute on function tee_internal.trip_role(uuid, uuid) to authenticated, service_role;
grant execute on function tee_internal.can_manage_trip(uuid, uuid) to authenticated, service_role;
grant execute on function tee_internal.can_score_player(uuid, uuid, uuid) to authenticated, service_role;

alter table public.trips enable row level security;
alter table public.trip_players enable row level security;
alter table public.course_cards enable row level security;
alter table public.course_card_holes enable row level security;
alter table public.round_holes enable row level security;
alter table public.trip_round_players enable row level security;
alter table public.trip_hole_scores enable row level security;
alter table public.trip_score_audit enable row level security;
alter table public.trip_leaderboard_snapshots enable row level security;
alter table public.trip_invites enable row level security;
alter table public.extension_sessions enable row level security;
alter table public.native_device_tokens enable row level security;
alter table public.live_activity_subscriptions enable row level security;
alter table public.trip_purchase_intents enable row level security;
alter table public.trip_entitlements enable row level security;

create policy "Trip members can read trips"
on public.trips for select to authenticated
using (tee_internal.is_trip_member(id));

create policy "Trip members can read roster"
on public.trip_players for select to authenticated
using (tee_internal.is_trip_member(trip_id));

create policy "Course card owners can read cards"
on public.course_cards for select to authenticated
using (owner_id = auth.uid());

create policy "Course card owners can read holes"
on public.course_card_holes for select to authenticated
using (
  exists (
    select 1 from public.course_cards cc
    where cc.id = course_card_holes.course_card_id
      and cc.owner_id = auth.uid()
  )
);

create policy "Trip members can read round holes"
on public.round_holes for select to authenticated
using (
  exists (
    select 1 from public.rounds r
    where r.id = round_holes.round_id
      and r.trip_id is not null
      and tee_internal.is_trip_member(r.trip_id)
  )
);

create policy "Trip members can read round roster"
on public.trip_round_players for select to authenticated
using (
  exists (
    select 1 from public.trip_players tp
    where tp.id = trip_round_players.trip_player_id
      and tee_internal.is_trip_member(tp.trip_id)
  )
);

create policy "Trip members can read scores"
on public.trip_hole_scores for select to authenticated
using (tee_internal.is_trip_member(trip_id));

create policy "Trip members can read score audit"
on public.trip_score_audit for select to authenticated
using (tee_internal.is_trip_member(trip_id));

create policy "Trip members can read snapshots"
on public.trip_leaderboard_snapshots for select to authenticated
using (tee_internal.is_trip_member(trip_id));

create policy "Purchasers can read purchase intents"
on public.trip_purchase_intents for select to authenticated
using (user_id = auth.uid());

create policy "Trip members can read entitlements"
on public.trip_entitlements for select to authenticated
using (tee_internal.is_trip_member(trip_id));

-- Preserve every legacy rounds policy and add participant visibility for the
-- native model. Expo's legacy direct inserts/updates are intentionally not
-- changed by this migration.
create policy "Trip members can view native rounds"
on public.rounds for select to authenticated
using (trip_id is not null and tee_internal.is_trip_member(trip_id));

-- Explicit privileges complement RLS. Sensitive bearer hashes and push tokens
-- have no client table privileges at all.
grant select on public.trips,
  public.trip_players,
  public.course_cards,
  public.course_card_holes,
  public.round_holes,
  public.trip_round_players,
  public.trip_hole_scores,
  public.trip_score_audit,
  public.trip_leaderboard_snapshots,
  public.trip_purchase_intents,
  public.trip_entitlements
to authenticated;

revoke insert, update, delete, truncate, references, trigger
on public.trips,
  public.trip_players,
  public.course_cards,
  public.course_card_holes,
  public.round_holes,
  public.trip_round_players,
  public.trip_hole_scores,
  public.trip_score_audit,
  public.trip_leaderboard_snapshots,
  public.trip_purchase_intents,
  public.trip_entitlements
from anon, authenticated;

revoke all
on public.trip_invites,
  public.extension_sessions,
  public.native_device_tokens,
  public.live_activity_subscriptions
from anon, authenticated;

revoke all on all tables in schema tee_internal from anon, authenticated;
