-- TEST-ONLY production-shaped legacy fixture.
--
-- This is the reviewed executable representation of the linked TeeCircle
-- baseline objects that native-v2 migrations touch: enum-backed
-- rounds/responses, profile-backed social foreign keys, the legacy visibility
-- view, trigger side effects, and legacy scorecard RLS. It is not a production
-- migration and must never be applied or marked as applied on a linked project.
-- Auth, Storage, extensions, grants, functions, and policies not exercised by
-- v2 remain intentionally out of scope.

-- Supabase-managed projects install shared extensions in this schema. Mirror
-- that layout so hardened function search paths are tested against production.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

grant usage on schema extensions to anon, authenticated, service_role;

-- Hosted Supabase grants function execution directly to its API roles through
-- postgres default privileges. Reproduce that behavior so migrations must
-- revoke explicit role grants, not only the generic PUBLIC grant.
alter default privileges for role postgres
  grant execute on functions to anon, authenticated, service_role;

-- The audited linked project has an empty supabase_realtime publication. The
-- native migration adds only its canonical snapshot table in migration 010.
create publication supabase_realtime;

create schema auth;

create table auth.users (
  id uuid primary key
);

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = pg_catalog
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create type public.friendship_status as enum ('pending', 'accepted');
create type public.response_status as enum ('yes', 'no', 'pending');
create type public.round_status as enum ('open', 'locked');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  username text,
  created_at timestamptz default now()
);

create unique index profiles_username_lower_key
  on public.profiles (lower(username))
  where username is not null;

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, user_id)
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_low uuid not null references public.profiles(id) on delete cascade,
  user_high uuid not null references public.profiles(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  status public.friendship_status not null default 'pending',
  created_at timestamptz default now(),
  accepted_at timestamptz,
  unique (user_low, user_high),
  constraint friendships_distinct_users_check check (user_low <> user_high)
);

create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references public.groups(id) on delete cascade,
  course_name text not null,
  tee_time timestamptz not null,
  holes integer check (holes in (9, 18)),
  walk_ride text check (walk_ride in ('walk', 'ride')),
  status public.round_status default 'open',
  created_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  course_place_id text,
  course_address text,
  course_lat double precision,
  course_lng double precision
);

create table public.round_responses (
  round_id uuid not null references public.rounds(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  response public.response_status default 'pending',
  responded_at timestamptz,
  primary key (round_id, user_id),
  constraint round_responses_round_id_user_id_key unique (round_id, user_id)
);

create table public.player_handicap_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handicap_index numeric(4,1),
  handicap_source text not null default 'teecircle',
  rounds_count integer not null default 0,
  last_calculated_at timestamptz,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint player_handicap_profiles_source_check
    check (handicap_source in ('teecircle'))
);

create table public.scorecards (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  entered_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'draft',
  holes integer not null check (holes in (9, 18)),
  gross_score integer,
  net_score integer,
  handicap_index_at_round numeric(4,1),
  course_handicap integer,
  playing_handicap integer,
  course_name text,
  tee_name text,
  tee_color text,
  course_rating numeric(4,1),
  slope_rating integer,
  par integer,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scorecards_status_check check (status in ('draft', 'completed')),
  constraint scorecards_score_check check (gross_score is null or gross_score > 0),
  constraint scorecards_slope_check
    check (slope_rating is null or slope_rating between 55 and 155),
  constraint scorecards_par_check check (par is null or par > 0),
  unique (round_id, player_id)
);

create table public.scorecard_holes (
  id uuid primary key default gen_random_uuid(),
  scorecard_id uuid not null references public.scorecards(id) on delete cascade,
  hole_number integer not null,
  par integer,
  stroke_index integer,
  yards integer,
  strokes integer,
  putts integer,
  fairway_hit boolean,
  gir boolean,
  penalties integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scorecard_holes_hole_check check (hole_number between 1 and 18),
  constraint scorecard_holes_par_check check (par is null or par > 0),
  constraint scorecard_holes_yards_check check (yards is null or yards > 0),
  constraint scorecard_holes_strokes_check check (strokes is null or strokes > 0),
  constraint scorecard_holes_putts_check check (putts is null or putts >= 0),
  constraint scorecard_holes_penalties_check check (penalties >= 0),
  unique (scorecard_id, hole_number)
);

create table public.handicap_differentials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  round_id uuid references public.rounds(id) on delete set null,
  scorecard_id uuid not null references public.scorecards(id) on delete cascade,
  holes integer not null check (holes in (9, 18)),
  adjusted_gross_score integer not null check (adjusted_gross_score > 0),
  course_rating numeric(4,1) not null,
  slope_rating integer not null check (slope_rating between 55 and 155),
  pcc integer not null default 0,
  differential numeric(5,2) not null,
  played_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (scorecard_id)
);

create index idx_scorecards_round_id on public.scorecards (round_id);
create index idx_scorecards_player_id on public.scorecards (player_id);
create index idx_handicap_differentials_user_id_played_at
  on public.handicap_differentials (user_id, played_at desc);

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.friendships enable row level security;
alter table public.rounds enable row level security;
alter table public.round_responses enable row level security;
alter table public.player_handicap_profiles enable row level security;
alter table public.scorecards enable row level security;
alter table public.scorecard_holes enable row level security;
alter table public.handicap_differentials enable row level security;

create policy "Users can view relevant profiles"
on public.profiles for select to authenticated
using (
  auth.uid() = id
  or exists (
    select 1 from public.friendships f
    where (f.user_low = auth.uid() and f.user_high = profiles.id)
       or (f.user_high = auth.uid() and f.user_low = profiles.id)
  )
);

create policy "Users can delete own profile"
on public.profiles for delete to authenticated
using (auth.uid() = id);

create policy "Users can view own friendships"
on public.friendships for select to authenticated
using (auth.uid() = user_low or auth.uid() = user_high);

create policy "Users can update own friendships"
on public.friendships for update to authenticated
using (auth.uid() = user_low or auth.uid() = user_high);

create policy "Group members can view groups"
on public.groups for select to authenticated
using (
  created_by = auth.uid()
  or exists (
    select 1 from public.group_members gm
    where gm.group_id = groups.id and gm.user_id = auth.uid()
  )
);

create policy "Users can create groups"
on public.groups for insert to authenticated
with check (created_by = auth.uid());

create policy "Group creators can manage groups"
on public.groups for update to authenticated
using (created_by = auth.uid())
with check (created_by = auth.uid());

create policy "Group creators can delete groups"
on public.groups for delete to authenticated
using (created_by = auth.uid());

create policy "Users can view their group memberships"
on public.group_members for select to authenticated
using (user_id = auth.uid());

create policy "Round creator can view round"
on public.rounds for select to authenticated
using (created_by = auth.uid());

create policy "Round creator can insert round"
on public.rounds for insert to authenticated
with check (created_by = auth.uid());

create policy "Round creator can delete round"
on public.rounds for delete to authenticated
using (created_by = auth.uid());

create policy "Invitee or round creator can view response"
on public.round_responses for select to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.rounds r
    where r.id = round_responses.round_id and r.created_by = auth.uid()
  )
);

create policy "Round creator can insert their own response"
on public.round_responses for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.rounds r
    where r.id = round_responses.round_id and r.created_by = auth.uid()
  )
);

create policy "Invitee can update their own response"
on public.round_responses for update to authenticated
using (user_id = auth.uid());

create policy "Round creator can delete responses"
on public.round_responses for delete to authenticated
using (
  exists (
    select 1 from public.rounds r
    where r.id = round_responses.round_id and r.created_by = auth.uid()
  )
);

create policy "Users can view own handicap profile or accepted friends"
on public.player_handicap_profiles for select to authenticated
using (
  auth.uid() = user_id
  or (
    not is_hidden
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.user_low = auth.uid() and f.user_high = player_handicap_profiles.user_id)
          or (f.user_high = auth.uid() and f.user_low = player_handicap_profiles.user_id)
        )
    )
  )
);

create policy "Users can manage own handicap profile"
on public.player_handicap_profiles for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Round participants can view scorecards"
on public.scorecards for select to authenticated
using (
  auth.uid() = player_id
  or exists (
    select 1 from public.rounds r
    where r.id = scorecards.round_id and r.created_by = auth.uid()
  )
  or exists (
    select 1 from public.round_responses rr
    where rr.round_id = scorecards.round_id
      and rr.user_id = auth.uid()
      and rr.response = 'yes'
  )
);

create policy "Players and round creators can manage scorecards"
on public.scorecards for all to authenticated
using (
  auth.uid() = player_id
  or exists (
    select 1 from public.rounds r
    where r.id = scorecards.round_id and r.created_by = auth.uid()
  )
)
with check (
  auth.uid() = player_id
  or exists (
    select 1 from public.rounds r
    where r.id = scorecards.round_id and r.created_by = auth.uid()
  )
);

create policy "Round participants can view scorecard holes"
on public.scorecard_holes for select to authenticated
using (
  exists (
    select 1 from public.scorecards s
    where s.id = scorecard_holes.scorecard_id
      and (
        s.player_id = auth.uid()
        or exists (
          select 1 from public.rounds r
          where r.id = s.round_id and r.created_by = auth.uid()
        )
        or exists (
          select 1 from public.round_responses rr
          where rr.round_id = s.round_id
            and rr.user_id = auth.uid()
            and rr.response = 'yes'
        )
      )
  )
);

create policy "Players and round creators can manage scorecard holes"
on public.scorecard_holes for all to authenticated
using (
  exists (
    select 1 from public.scorecards s
    where s.id = scorecard_holes.scorecard_id
      and (
        s.player_id = auth.uid()
        or exists (
          select 1 from public.rounds r
          where r.id = s.round_id and r.created_by = auth.uid()
        )
      )
  )
)
with check (
  exists (
    select 1 from public.scorecards s
    where s.id = scorecard_holes.scorecard_id
      and (
        s.player_id = auth.uid()
        or exists (
          select 1 from public.rounds r
          where r.id = s.round_id and r.created_by = auth.uid()
        )
      )
  )
);

create policy "Users can view own handicap differentials or accepted friends"
on public.handicap_differentials for select to authenticated
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and (
        (f.user_low = auth.uid() and f.user_high = handicap_differentials.user_id)
        or (f.user_high = auth.uid() and f.user_low = handicap_differentials.user_id)
      )
  )
);

create policy "Users can manage own handicap differentials"
on public.handicap_differentials for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create view public.visible_rounds as
select distinct
  r.id,
  r.group_id,
  r.course_name,
  r.course_place_id,
  r.course_address,
  r.course_lat,
  r.course_lng,
  r.tee_time,
  r.holes,
  r.walk_ride,
  r.status,
  r.created_by,
  r.created_at
from public.rounds r
left join public.round_responses rr on rr.round_id = r.id
where r.created_by = auth.uid() or rr.user_id = auth.uid();

create or replace function public.create_creator_response()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.round_responses (round_id, user_id, response, responded_at)
  values (new.id, new.created_by, 'yes', now())
  on conflict (round_id, user_id) do nothing;
  return new;
end;
$$;

create trigger on_round_created_add_creator_response
after insert on public.rounds
for each row execute function public.create_creator_response();

create or replace function public.lock_round_if_ready()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if (
    select count(*)
    from public.round_responses rr
    where rr.round_id = new.round_id and rr.response = 'yes'
  ) >= 2 then
    update public.rounds r set status = 'locked' where r.id = new.round_id;
  end if;
  return new;
end;
$$;

create trigger check_round_lock
after update on public.round_responses
for each row execute function public.lock_round_if_ready();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_player_handicap_profiles_updated_at
before update on public.player_handicap_profiles
for each row execute function public.set_updated_at();

create trigger set_scorecards_updated_at
before update on public.scorecards
for each row execute function public.set_updated_at();

create trigger set_scorecard_holes_updated_at
before update on public.scorecard_holes
for each row execute function public.set_updated_at();

create or replace function public.invite_friend_to_round(
  p_round_id uuid,
  p_friend_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_created_by uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select r.created_by into v_created_by
  from public.rounds r where r.id = p_round_id;
  if not found then
    raise exception 'Round not found';
  end if;
  if v_created_by <> v_user_id then
    raise exception 'Only the creator can invite';
  end if;
  if not exists (
    select 1 from public.friendships f
    where f.user_low = least(v_user_id, p_friend_id)
      and f.user_high = greatest(v_user_id, p_friend_id)
      and f.status = 'accepted'
  ) then
    raise exception 'Not friends';
  end if;

  insert into public.round_responses (round_id, user_id, response)
  values (p_round_id, p_friend_id, 'pending')
  on conflict (round_id, user_id) do nothing;
  return true;
end;
$$;

create or replace function public.delete_user_account()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  delete from public.friendships
  where user_low = v_user_id or user_high = v_user_id;
  delete from public.group_members where user_id = v_user_id;
  delete from public.round_responses where user_id = v_user_id;
  if to_regclass('public.push_tokens') is not null then
    delete from public.push_tokens where user_id = v_user_id;
  end if;
  delete from public.rounds where created_by = v_user_id;
  delete from public.groups where created_by = v_user_id;
  delete from public.profiles where id = v_user_id;
end;
$$;

grant select, insert, update, delete on
  public.profiles,
  public.groups,
  public.group_members,
  public.friendships,
  public.rounds,
  public.round_responses,
  public.player_handicap_profiles,
  public.scorecards,
  public.scorecard_holes,
  public.handicap_differentials
to authenticated;
grant select on public.visible_rounds to authenticated;
grant execute on function public.invite_friend_to_round(uuid, uuid)
  to authenticated;
grant execute on function public.delete_user_account() to authenticated;
