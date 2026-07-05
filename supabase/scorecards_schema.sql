create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.player_handicap_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handicap_index numeric(4,1),
  handicap_source text not null default 'teecircle',
  rounds_count integer not null default 0,
  last_calculated_at timestamptz,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint player_handicap_profiles_source_check check (handicap_source in ('teecircle'))
);

create table if not exists public.scorecards (
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
  constraint scorecards_slope_check check (slope_rating is null or slope_rating between 55 and 155),
  constraint scorecards_par_check check (par is null or par > 0),
  unique (round_id, player_id)
);

create table if not exists public.scorecard_holes (
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

create table if not exists public.handicap_differentials (
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

create index if not exists idx_scorecards_round_id on public.scorecards (round_id);
create index if not exists idx_scorecards_player_id on public.scorecards (player_id);
create index if not exists idx_handicap_differentials_user_id_played_at
  on public.handicap_differentials (user_id, played_at desc);

drop trigger if exists set_player_handicap_profiles_updated_at on public.player_handicap_profiles;
create trigger set_player_handicap_profiles_updated_at
before update on public.player_handicap_profiles
for each row
execute function public.set_updated_at();

drop trigger if exists set_scorecards_updated_at on public.scorecards;
create trigger set_scorecards_updated_at
before update on public.scorecards
for each row
execute function public.set_updated_at();

drop trigger if exists set_scorecard_holes_updated_at on public.scorecard_holes;
create trigger set_scorecard_holes_updated_at
before update on public.scorecard_holes
for each row
execute function public.set_updated_at();
