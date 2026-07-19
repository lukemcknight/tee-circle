set lock_timeout = '10s';
set statement_timeout = '5min';

-- TeeCircle 2.0 additive schema.
--
-- IMPORTANT: this migration deliberately does not recreate or guess the
-- production legacy schema. It must be applied after a verified baseline that
-- contains public.rounds. Every legacy table and column remains compatible
-- with the Expo client.


create extension if not exists pgcrypto;

do $$
begin
  if to_regclass('public.rounds') is null then
    raise exception using
      errcode = 'P0001',
      message = 'legacy_schema_missing',
      detail = 'TeeCircle 2.0 migrations require a verified baseline containing public.rounds; do not fabricate one from client types.';
  end if;
end
$$;

create schema if not exists tee_internal;
revoke all on schema tee_internal from public;

create or replace function tee_internal.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = statement_timestamp();
  return new;
end;
$$;

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  public_id uuid not null default gen_random_uuid() unique,
  owner_id uuid not null references auth.users(id) on delete restrict,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  timezone text not null default 'America/New_York',
  status text not null default 'draft',
  enabled_formats text[] not null default array['stableford']::text[],
  primary_format text not null default 'stableford',
  scoring_mode text not null default 'net',
  score_revision bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trips_name_check check (char_length(btrim(name)) between 1 and 120),
  constraint trips_dates_check check (ends_on >= starts_on),
  constraint trips_timezone_check check (char_length(btrim(timezone)) between 1 and 80),
  constraint trips_status_check check (status in ('draft', 'ready', 'live', 'completed', 'archived')),
  constraint trips_enabled_formats_check check (
    enabled_formats = array['skins']::text[]
    or enabled_formats = array['stableford']::text[]
    or enabled_formats = array['skins', 'stableford']::text[]
    or enabled_formats = array['stableford', 'skins']::text[]
  ),
  constraint trips_primary_format_check check (
    primary_format in ('skins', 'stableford')
    and primary_format = any(enabled_formats)
  ),
  constraint trips_scoring_mode_check check (scoring_mode in ('gross', 'net')),
  constraint trips_revision_check check (score_revision >= 0)
);

create trigger set_trips_updated_at
before update on public.trips
for each row execute function tee_internal.set_updated_at();

-- Add only native-trip columns to legacy rounds. The legacy status column is
-- intentionally untouched because Expo currently uses values such as locked.
alter table public.rounds
  add column if not exists trip_id uuid,
  add column if not exists trip_order smallint,
  add column if not exists public_id uuid,
  add column if not exists trip_round_status text,
  add column if not exists legacy_source_round_id uuid,
  add column if not exists native_updated_at timestamptz default now();

-- Install the volatile UUID default only after the column exists. Adding a
-- column with gen_random_uuid() as its default rewrites every legacy round;
-- setting the default separately leaves existing rows null while new native
-- (and legacy) inserts receive a UUID without a table rewrite.
alter table public.rounds
  alter column public_id set default gen_random_uuid();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.rounds'::regclass
      and conname = 'rounds_trip_id_fkey'
  ) then
    alter table public.rounds
      add constraint rounds_trip_id_fkey
      foreign key (trip_id) references public.trips(id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.rounds'::regclass
      and conname = 'rounds_trip_order_check'
  ) then
    alter table public.rounds
      add constraint rounds_trip_order_check
      check (trip_order is null or trip_order between 1 and 100);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.rounds'::regclass
      and conname = 'rounds_trip_round_status_check'
  ) then
    alter table public.rounds
      add constraint rounds_trip_round_status_check
      check (trip_round_status is null or trip_round_status in ('scheduled', 'live', 'completed'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.rounds'::regclass
      and conname = 'rounds_legacy_source_round_id_fkey'
  ) then
    alter table public.rounds
      add constraint rounds_legacy_source_round_id_fkey
      foreign key (legacy_source_round_id) references public.rounds(id) on delete set null;
  end if;
end
$$;

create unique index if not exists rounds_public_id_key
  on public.rounds (public_id)
  where public_id is not null;
create unique index if not exists rounds_trip_order_key
  on public.rounds (trip_id, trip_order)
  where trip_id is not null;
create index if not exists rounds_trip_id_idx on public.rounds (trip_id);

-- Supabase grants broad public-table privileges to anon/authenticated through
-- postgres' default ACL. The legacy rounds table must stay writable for Expo,
-- but clients must never attach a row to the native trip graph directly. Put
-- the restrictive boundary in the same transaction that adds trip_id so
-- there is no deployment window before the later release-integrity migration.
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

create table public.trip_players (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  claimed_user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  role text not null default 'player',
  rsvp text not null default 'pending',
  handicap_snapshot numeric(4,1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trip_players_name_check check (char_length(btrim(display_name)) between 1 and 80),
  constraint trip_players_role_check check (role in ('captain', 'scorer', 'player')),
  constraint trip_players_rsvp_check check (rsvp in ('pending', 'yes', 'no')),
  constraint trip_players_handicap_check check (
    handicap_snapshot is null or handicap_snapshot between -10 and 54
  )
);

create unique index trip_players_claimed_user_key
  on public.trip_players (trip_id, claimed_user_id)
  where claimed_user_id is not null;
create unique index trip_players_display_name_key
  on public.trip_players (trip_id, lower(display_name));
create index trip_players_trip_idx on public.trip_players (trip_id);

create trigger set_trip_players_updated_at
before update on public.trip_players
for each row execute function tee_internal.set_updated_at();

create table public.course_cards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  name text not null,
  course_name text not null,
  hole_count smallint not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_cards_name_check check (char_length(btrim(name)) between 1 and 120),
  constraint course_cards_course_name_check check (char_length(btrim(course_name)) between 1 and 160),
  constraint course_cards_hole_count_check check (hole_count in (9, 18))
);

create index course_cards_owner_idx on public.course_cards (owner_id, created_at desc);

create trigger set_course_cards_updated_at
before update on public.course_cards
for each row execute function tee_internal.set_updated_at();

create table public.course_card_holes (
  course_card_id uuid not null references public.course_cards(id) on delete cascade,
  hole_number smallint not null,
  par smallint not null,
  stroke_index smallint,
  yards smallint,
  primary key (course_card_id, hole_number),
  constraint course_card_holes_number_check check (hole_number between 1 and 18),
  constraint course_card_holes_par_check check (par between 3 and 6),
  constraint course_card_holes_stroke_index_check check (stroke_index is null or stroke_index between 1 and 18),
  constraint course_card_holes_yards_check check (yards is null or yards between 40 and 900)
);

create unique index course_card_holes_stroke_index_key
  on public.course_card_holes (course_card_id, stroke_index)
  where stroke_index is not null;

create table public.round_holes (
  round_id uuid not null references public.rounds(id) on delete cascade,
  hole_number smallint not null,
  par smallint not null,
  stroke_index smallint,
  yards smallint,
  primary key (round_id, hole_number),
  constraint round_holes_number_check check (hole_number between 1 and 18),
  constraint round_holes_par_check check (par between 3 and 6),
  constraint round_holes_stroke_index_check check (stroke_index is null or stroke_index between 1 and 18),
  constraint round_holes_yards_check check (yards is null or yards between 40 and 900)
);

create unique index round_holes_stroke_index_key
  on public.round_holes (round_id, stroke_index)
  where stroke_index is not null;

create table public.trip_round_players (
  round_id uuid not null references public.rounds(id) on delete cascade,
  trip_player_id uuid not null references public.trip_players(id) on delete cascade,
  course_handicap smallint,
  playing_handicap smallint,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (round_id, trip_player_id),
  constraint trip_round_players_course_handicap_check check (course_handicap is null or course_handicap between -10 and 72),
  constraint trip_round_players_playing_handicap_check check (playing_handicap is null or playing_handicap between -10 and 72),
  constraint trip_round_players_status_check check (status in ('active', 'withdrawn'))
);

create index trip_round_players_player_idx on public.trip_round_players (trip_player_id);

create trigger set_trip_round_players_updated_at
before update on public.trip_round_players
for each row execute function tee_internal.set_updated_at();

create table public.trip_hole_scores (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  round_id uuid not null,
  trip_player_id uuid not null,
  hole_number smallint not null,
  strokes smallint not null,
  penalties smallint not null default 0,
  recorded_by_user_id uuid not null references auth.users(id) on delete restrict,
  revision bigint not null,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trip_hole_scores_strokes_check check (strokes between 1 and 30),
  constraint trip_hole_scores_penalties_check check (penalties between 0 and 30),
  constraint trip_hole_scores_revision_check check (revision > 0),
  constraint trip_hole_scores_round_player_fkey
    foreign key (round_id, trip_player_id)
    references public.trip_round_players(round_id, trip_player_id) on delete cascade,
  constraint trip_hole_scores_round_hole_fkey
    foreign key (round_id, hole_number)
    references public.round_holes(round_id, hole_number) on delete restrict,
  unique (round_id, trip_player_id, hole_number),
  unique (recorded_by_user_id, idempotency_key)
);

create index trip_hole_scores_trip_revision_idx
  on public.trip_hole_scores (trip_id, revision desc);
create index trip_hole_scores_round_idx
  on public.trip_hole_scores (round_id, hole_number);

create trigger set_trip_hole_scores_updated_at
before update on public.trip_hole_scores
for each row execute function tee_internal.set_updated_at();

create table public.trip_score_audit (
  id bigint generated always as identity primary key,
  score_id uuid not null references public.trip_hole_scores(id) on delete restrict,
  trip_id uuid not null references public.trips(id) on delete restrict,
  round_id uuid not null references public.rounds(id) on delete restrict,
  trip_player_id uuid not null references public.trip_players(id) on delete restrict,
  hole_number smallint not null,
  previous_strokes smallint,
  strokes smallint not null,
  previous_penalties smallint,
  penalties smallint not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  revision bigint not null,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  unique (trip_id, revision),
  unique (actor_user_id, idempotency_key)
);

create index trip_score_audit_score_idx on public.trip_score_audit (score_id, revision desc);

create table public.trip_leaderboard_snapshots (
  trip_id uuid not null references public.trips(id) on delete cascade,
  revision bigint not null,
  scoring_engine_version text not null,
  payload jsonb not null,
  is_final boolean not null default false,
  computed_at timestamptz not null default now(),
  primary key (trip_id, revision),
  constraint trip_leaderboard_snapshots_revision_check check (revision >= 0),
  constraint trip_leaderboard_snapshots_payload_check check (
    jsonb_typeof(payload) = 'object'
    and payload @> '{"schemaVersion": 1}'::jsonb
  )
);

create index trip_leaderboard_snapshots_latest_idx
  on public.trip_leaderboard_snapshots (trip_id, revision desc);

create table public.trip_invites (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  token_hash bytea not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz,
  revoked_at timestamptz,
  max_uses integer,
  use_count integer not null default 0,
  created_at timestamptz not null default now(),
  constraint trip_invites_max_uses_check check (max_uses is null or max_uses between 1 and 100000),
  constraint trip_invites_use_count_check check (use_count >= 0)
);

create index trip_invites_trip_idx on public.trip_invites (trip_id, created_at desc);

create table public.extension_sessions (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  trip_player_id uuid not null references public.trip_players(id) on delete cascade,
  device_id text not null,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  constraint extension_sessions_device_id_check check (char_length(device_id) between 8 and 200)
);

create index extension_sessions_user_device_idx
  on public.extension_sessions (user_id, device_id, created_at desc);

create table public.native_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  provider text not null default 'apns',
  token text not null,
  environment text not null,
  bundle_id text not null,
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint native_device_tokens_device_id_check check (char_length(device_id) between 8 and 200),
  constraint native_device_tokens_provider_check check (provider in ('apns')),
  constraint native_device_tokens_environment_check check (environment in ('sandbox', 'production')),
  constraint native_device_tokens_token_check check (token ~ '^[A-Fa-f0-9]{32,200}$'),
  constraint native_device_tokens_bundle_id_check check (char_length(bundle_id) between 3 and 200),
  unique (token, environment),
  unique (user_id, device_id, provider, environment, bundle_id)
);

create table public.live_activity_subscriptions (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  activity_id text not null,
  push_token text not null,
  environment text not null,
  expires_at timestamptz,
  ended_at timestamptz,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint live_activity_device_id_check check (char_length(device_id) between 8 and 200),
  constraint live_activity_id_check check (char_length(activity_id) between 1 and 200),
  constraint live_activity_environment_check check (environment in ('sandbox', 'production')),
  constraint live_activity_push_token_check check (push_token ~ '^[A-Fa-f0-9]{32,200}$'),
  unique (push_token, environment),
  unique (user_id, device_id, activity_id)
);

create index live_activity_trip_active_idx
  on public.live_activity_subscriptions (trip_id, environment)
  where ended_at is null;

create table public.trip_purchase_intents (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  product_id text not null default 'com.teecircle.app.trip_unlock_2999',
  status text not null default 'pending',
  revenuecat_transaction_id text unique,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trip_purchase_intents_product_check check (product_id = 'com.teecircle.app.trip_unlock_2999'),
  constraint trip_purchase_intents_status_check check (status in ('pending', 'verified', 'cancelled', 'expired'))
);

create index trip_purchase_intents_trip_idx
  on public.trip_purchase_intents (trip_id, created_at desc);

create trigger set_trip_purchase_intents_updated_at
before update on public.trip_purchase_intents
for each row execute function tee_internal.set_updated_at();

create table public.trip_entitlements (
  trip_id uuid primary key references public.trips(id) on delete cascade,
  purchase_intent_id uuid not null unique references public.trip_purchase_intents(id) on delete restrict,
  product_id text not null,
  revenuecat_transaction_id text not null unique,
  verified_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint trip_entitlements_product_check check (product_id = 'com.teecircle.app.trip_unlock_2999')
);

-- Private transactional outbox. Repeated notifications collapse onto the same
-- (trip, revision); workers lease rows so retries are safe.
create table tee_internal.leaderboard_recompute_jobs (
  trip_id uuid not null references public.trips(id) on delete cascade,
  revision bigint not null,
  status text not null default 'pending',
  attempts smallint not null default 0,
  available_at timestamptz not null default now(),
  leased_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (trip_id, revision),
  constraint leaderboard_recompute_jobs_status_check check (status in ('pending', 'processing', 'completed', 'failed')),
  constraint leaderboard_recompute_jobs_attempts_check check (attempts between 0 and 25)
);

create index leaderboard_recompute_jobs_ready_idx
  on tee_internal.leaderboard_recompute_jobs (available_at, created_at)
  where status in ('pending', 'failed');

create table tee_internal.public_rate_limits (
  subject_hash bytea not null,
  route text not null,
  window_started_at timestamptz not null,
  request_count integer not null default 1,
  primary key (subject_hash, route, window_started_at),
  constraint public_rate_limits_count_check check (request_count > 0)
);

create table tee_internal.command_idempotency (
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key uuid not null,
  operation text not null,
  request_hash bytea not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, idempotency_key)
);

create table tee_internal.runtime_flags (
  key text primary key,
  enabled boolean not null,
  updated_at timestamptz not null default now()
);

insert into tee_internal.runtime_flags (key, enabled)
values
  ('native_writes_enabled', false),
  ('public_previews_enabled', false),
  ('live_activity_pushes_enabled', false),
  ('purchases_required', true)
on conflict (key) do nothing;

-- Defense-in-depth consistency checks for RPC and service-role writes.
create or replace function tee_internal.enforce_trip_round_player_consistency()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_round_trip uuid;
  v_player_trip uuid;
begin
  select r.trip_id into v_round_trip from public.rounds r where r.id = new.round_id;
  select p.trip_id into v_player_trip from public.trip_players p where p.id = new.trip_player_id;
  if v_round_trip is null or v_player_trip is null or v_round_trip <> v_player_trip then
    raise exception using errcode = '23514', message = 'trip_round_player_mismatch';
  end if;
  if tg_table_name = 'trip_hole_scores' then
    if new.trip_id <> v_round_trip then
      raise exception using errcode = '23514', message = 'trip_score_trip_mismatch';
    end if;
  end if;
  return new;
end;
$$;

create trigger enforce_trip_round_players_consistency
before insert or update on public.trip_round_players
for each row execute function tee_internal.enforce_trip_round_player_consistency();

create trigger enforce_trip_hole_scores_consistency
before insert or update on public.trip_hole_scores
for each row execute function tee_internal.enforce_trip_round_player_consistency();

create or replace function tee_internal.enforce_round_hole_bounds()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_holes integer;
begin
  select coalesce(r.holes, 18) into v_holes from public.rounds r where r.id = new.round_id;
  if v_holes is null or new.hole_number > v_holes then
    raise exception using errcode = '23514', message = 'hole_out_of_round_bounds';
  end if;
  return new;
end;
$$;

create trigger enforce_round_hole_bounds
before insert or update on public.round_holes
for each row execute function tee_internal.enforce_round_hole_bounds();

comment on table public.trips is 'Native TeeCircle 2.0 multi-round trip; additive to legacy Expo rounds.';
comment on table public.trip_leaderboard_snapshots is 'Append-only authoritative broadcast snapshots consumed by every client surface.';
comment on table tee_internal.leaderboard_recompute_jobs is 'Transactional snapshot recompute outbox; never exposed through PostgREST.';

-- Fail closed before this transaction becomes visible. Supabase's postgres
-- default ACL grants anon/authenticated every table privilege, so waiting for
-- the next migration to enable RLS would create a brief direct-write window.
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

revoke all
on public.trips,
  public.trip_players,
  public.course_cards,
  public.course_card_holes,
  public.round_holes,
  public.trip_round_players,
  public.trip_hole_scores,
  public.trip_score_audit,
  public.trip_leaderboard_snapshots,
  public.trip_invites,
  public.extension_sessions,
  public.native_device_tokens,
  public.live_activity_subscriptions,
  public.trip_purchase_intents,
  public.trip_entitlements
from anon, authenticated;

revoke all on sequence public.trip_score_audit_id_seq from anon, authenticated;
revoke all on all tables in schema tee_internal from public, anon, authenticated;
revoke all on all sequences in schema tee_internal from public, anon, authenticated;
revoke all on all functions in schema tee_internal from public, anon, authenticated;
