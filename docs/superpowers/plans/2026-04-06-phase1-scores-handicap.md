# Phase 1: Scores + Handicap Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players enter scores for rounds and track an in-app handicap index that updates automatically.

**Architecture:** Add four new Supabase tables (`scorecards`, `scorecard_holes`, `player_handicap_profiles`, `handicap_differentials`) with RLS policies and an RPC for handicap recalculation. On the client, add two data-fetching hooks, a score entry screen, and extend RoundDetail and Profile screens to surface scorecard and handicap data.

**Tech Stack:** Supabase (Postgres, RLS, RPCs), React Native / Expo, TypeScript, React Navigation

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `supabase/scorecards_tables.sql` | DDL for `scorecards` and `scorecard_holes` tables |
| `supabase/handicap_tables.sql` | DDL for `player_handicap_profiles` and `handicap_differentials` tables |
| `supabase/scorecards_policies.sql` | RLS policies for scorecard tables |
| `supabase/handicap_policies.sql` | RLS policies for handicap tables |
| `supabase/recalculate_handicap_rpc.sql` | RPC: `recalculate_handicap` — computes handicap index from differentials |
| `src/hooks/useScorecards.ts` | Hook to fetch scorecards for a round |
| `src/hooks/useHandicap.ts` | Hook to fetch a player's handicap profile + differentials |
| `src/screens/RoundScoreScreen.tsx` | Score entry screen (total score + optional hole-by-hole) |

### Modified Files

| File | Changes |
|------|---------|
| `src/types.ts` | Add `Scorecard`, `ScorecardHole`, `HandicapProfile`, `HandicapDifferential` types |
| `src/lib/supabase.ts` | Add Database type entries for new tables and RPCs |
| `src/navigation/types.ts` | Add `RoundScore` route |
| `src/navigation/AppNavigator.tsx` | Register `RoundScoreScreen` |
| `src/context/DataContext.tsx` | Add `createScorecard`, `saveHoleScores`, `finalizeScorecard` mutations |
| `src/screens/RoundDetailScreen.tsx` | Add scorecard summary section + "Enter Scores" button |
| `src/screens/ProfileScreen.tsx` | Add handicap display card |

---

## Task 1: Database Tables — Scorecards

**Files:**
- Create: `supabase/scorecards_tables.sql`

- [ ] **Step 1: Write the scorecards DDL**

```sql
-- Scorecard and hole-by-hole score tables for TeeCircle.

-- scorecards: one row per player per round
create table if not exists public.scorecards (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id),
  entered_by uuid not null references auth.users(id),
  status text not null default 'draft',
  holes integer not null check (holes in (9, 18)),
  gross_score integer null,
  net_score integer null,
  handicap_index_at_round numeric(4,1) null,
  course_handicap integer null,
  playing_handicap integer null,
  course_name text null,
  tee_name text null,
  tee_color text null,
  course_rating numeric(4,1) null,
  slope_rating integer null,
  par integer null,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scorecards_round_player_unique unique (round_id, player_id)
);

-- scorecard_holes: one row per hole per scorecard
create table if not exists public.scorecard_holes (
  id uuid primary key default gen_random_uuid(),
  scorecard_id uuid not null references public.scorecards(id) on delete cascade,
  hole_number integer not null,
  par integer null,
  stroke_index integer null,
  yards integer null,
  strokes integer null,
  putts integer null,
  fairway_hit boolean null,
  gir boolean null,
  penalties integer null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scorecard_holes_card_hole_unique unique (scorecard_id, hole_number)
);
```

- [ ] **Step 2: Apply migration to Supabase**

Run in the Supabase SQL editor or via CLI:
```bash
# If using supabase CLI:
supabase db push
# Otherwise, paste the SQL into the Supabase dashboard SQL editor and run it.
```

- [ ] **Step 3: Commit**

```bash
git add supabase/scorecards_tables.sql
git commit -m "feat: add scorecards and scorecard_holes tables"
```

---

## Task 2: Database Tables — Handicap

**Files:**
- Create: `supabase/handicap_tables.sql`

- [ ] **Step 1: Write the handicap DDL**

```sql
-- Handicap tracking tables for TeeCircle.

-- player_handicap_profiles: one row per user
create table if not exists public.player_handicap_profiles (
  user_id uuid primary key references auth.users(id),
  handicap_index numeric(4,1) null,
  handicap_source text not null default 'teecircle',
  last_calculated_at timestamptz null,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- handicap_differentials: one row per score posted toward handicap
create table if not exists public.handicap_differentials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  round_id uuid null references public.rounds(id) on delete set null,
  scorecard_id uuid not null references public.scorecards(id) on delete cascade,
  holes integer not null check (holes in (9, 18)),
  adjusted_gross_score integer not null,
  course_rating numeric(4,1) not null,
  slope_rating integer not null,
  pcc integer not null default 0,
  differential numeric(5,2) not null,
  played_at timestamptz not null,
  created_at timestamptz not null default now()
);
```

- [ ] **Step 2: Apply migration to Supabase**

- [ ] **Step 3: Commit**

```bash
git add supabase/handicap_tables.sql
git commit -m "feat: add player_handicap_profiles and handicap_differentials tables"
```

---

## Task 3: RLS Policies — Scorecards

**Files:**
- Create: `supabase/scorecards_policies.sql`

- [ ] **Step 1: Write the scorecard RLS policies**

```sql
-- RLS policies for scorecards and scorecard_holes.

alter table public.scorecards enable row level security;
alter table public.scorecard_holes enable row level security;

-- Drop existing policies for idempotency
do $$
declare pol record;
begin
  for pol in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename in ('scorecards', 'scorecard_holes')
  loop
    execute format('drop policy if exists %I on public.%I', pol.policyname, pol.tablename);
  end loop;
end
$$;

-- Scorecards: player can view their own
create policy "Player can view own scorecards"
on public.scorecards for select
using (player_id = auth.uid());

-- Scorecards: round participants can view all scorecards for their rounds
create policy "Round participants can view round scorecards"
on public.scorecards for select
using (
  exists (
    select 1 from public.round_responses rr
    where rr.round_id = scorecards.round_id
      and rr.user_id = auth.uid()
  )
);

-- Scorecards: round creator can view all scorecards for their rounds
create policy "Round creator can view round scorecards"
on public.scorecards for select
using (
  exists (
    select 1 from public.rounds r
    where r.id = scorecards.round_id
      and r.created_by = auth.uid()
  )
);

-- Scorecards: player or round creator can insert
create policy "Player or creator can insert scorecard"
on public.scorecards for insert
with check (
  player_id = auth.uid()
  or exists (
    select 1 from public.rounds r
    where r.id = round_id
      and r.created_by = auth.uid()
  )
);

-- Scorecards: player or round creator can update
create policy "Player or creator can update scorecard"
on public.scorecards for update
using (
  player_id = auth.uid()
  or exists (
    select 1 from public.rounds r
    where r.id = scorecards.round_id
      and r.created_by = auth.uid()
  )
);

-- Scorecard holes: visible if parent scorecard is visible (player or round participant)
create policy "Hole scores visible to scorecard viewers"
on public.scorecard_holes for select
using (
  exists (
    select 1 from public.scorecards sc
    where sc.id = scorecard_holes.scorecard_id
      and (
        sc.player_id = auth.uid()
        or exists (
          select 1 from public.round_responses rr
          where rr.round_id = sc.round_id
            and rr.user_id = auth.uid()
        )
        or exists (
          select 1 from public.rounds r
          where r.id = sc.round_id
            and r.created_by = auth.uid()
        )
      )
  )
);

-- Scorecard holes: insert if user owns or created round for the parent scorecard
create policy "Player or creator can insert hole scores"
on public.scorecard_holes for insert
with check (
  exists (
    select 1 from public.scorecards sc
    where sc.id = scorecard_id
      and (
        sc.player_id = auth.uid()
        or exists (
          select 1 from public.rounds r
          where r.id = sc.round_id
            and r.created_by = auth.uid()
        )
      )
  )
);

-- Scorecard holes: update if user owns or created round for the parent scorecard
create policy "Player or creator can update hole scores"
on public.scorecard_holes for update
using (
  exists (
    select 1 from public.scorecards sc
    where sc.id = scorecard_holes.scorecard_id
      and (
        sc.player_id = auth.uid()
        or exists (
          select 1 from public.rounds r
          where r.id = sc.round_id
            and r.created_by = auth.uid()
        )
      )
  )
);
```

- [ ] **Step 2: Apply migration to Supabase**

- [ ] **Step 3: Commit**

```bash
git add supabase/scorecards_policies.sql
git commit -m "feat: add RLS policies for scorecards and scorecard_holes"
```

---

## Task 4: RLS Policies — Handicap

**Files:**
- Create: `supabase/handicap_policies.sql`

- [ ] **Step 1: Write the handicap RLS policies**

```sql
-- RLS policies for handicap tables.

alter table public.player_handicap_profiles enable row level security;
alter table public.handicap_differentials enable row level security;

-- Drop existing policies for idempotency
do $$
declare pol record;
begin
  for pol in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename in ('player_handicap_profiles', 'handicap_differentials')
  loop
    execute format('drop policy if exists %I on public.%I', pol.policyname, pol.tablename);
  end loop;
end
$$;

-- Handicap profiles: user can view their own
create policy "User can view own handicap profile"
on public.player_handicap_profiles for select
using (user_id = auth.uid());

-- Handicap profiles: accepted friends can view unless hidden
create policy "Friends can view handicap profile"
on public.player_handicap_profiles for select
using (
  is_hidden = false
  and exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and (
        (f.user_low = auth.uid() and f.user_high = player_handicap_profiles.user_id)
        or (f.user_high = auth.uid() and f.user_low = player_handicap_profiles.user_id)
      )
  )
);

-- Handicap profiles: user can insert their own
create policy "User can insert own handicap profile"
on public.player_handicap_profiles for insert
with check (user_id = auth.uid());

-- Handicap profiles: user can update their own
create policy "User can update own handicap profile"
on public.player_handicap_profiles for update
using (user_id = auth.uid());

-- Handicap differentials: user can view their own
create policy "User can view own differentials"
on public.handicap_differentials for select
using (user_id = auth.uid());

-- Handicap differentials: insert own only
create policy "User can insert own differentials"
on public.handicap_differentials for insert
with check (user_id = auth.uid());
```

- [ ] **Step 2: Apply migration to Supabase**

- [ ] **Step 3: Commit**

```bash
git add supabase/handicap_policies.sql
git commit -m "feat: add RLS policies for handicap tables"
```

---

## Task 5: Handicap Recalculation RPC

**Files:**
- Create: `supabase/recalculate_handicap_rpc.sql`

The handicap formula: `differential = (113 / slope_rating) * (adjusted_gross_score - course_rating)`. The index is the average of the best 8 of the most recent 20 differentials (scaled down based on count if fewer than 20).

- [ ] **Step 1: Write the RPC**

```sql
-- RPC to recalculate a player's handicap index from their differentials.
-- Uses best-of-N from most recent 20 differentials.
-- Lookup table: 3→1, 4→1, 5→1, 6→1, 7-8→2, 9-10→3, 11-12→4, 13-14→5, 15-16→6, 17→7, 18→8, 19→8, 20→8

create or replace function public.recalculate_handicap(p_user_id uuid)
returns numeric
language plpgsql
security definer
as $$
declare
  v_count integer;
  v_take integer;
  v_index numeric(4,1);
begin
  -- Count recent differentials
  select count(*) into v_count
  from (
    select 1 from public.handicap_differentials
    where user_id = p_user_id
    order by played_at desc
    limit 20
  ) sub;

  if v_count < 3 then
    -- Not enough rounds to calculate handicap
    update public.player_handicap_profiles
    set handicap_index = null,
        last_calculated_at = now(),
        updated_at = now()
    where user_id = p_user_id;
    return null;
  end if;

  -- Determine how many best differentials to use
  v_take := case
    when v_count <= 6  then 1
    when v_count <= 8  then 2
    when v_count <= 10 then 3
    when v_count <= 12 then 4
    when v_count <= 14 then 5
    when v_count <= 16 then 6
    when v_count = 17  then 7
    else 8
  end;

  -- Calculate index: average of best v_take differentials from most recent 20
  select round(avg(differential)::numeric, 1) into v_index
  from (
    select differential
    from (
      select differential
      from public.handicap_differentials
      where user_id = p_user_id
      order by played_at desc
      limit 20
    ) recent
    order by differential asc
    limit v_take
  ) best;

  -- Upsert the handicap profile
  insert into public.player_handicap_profiles (user_id, handicap_index, last_calculated_at, updated_at)
  values (p_user_id, v_index, now(), now())
  on conflict (user_id) do update
  set handicap_index = v_index,
      last_calculated_at = now(),
      updated_at = now();

  return v_index;
end;
$$;
```

- [ ] **Step 2: Apply migration to Supabase**

- [ ] **Step 3: Commit**

```bash
git add supabase/recalculate_handicap_rpc.sql
git commit -m "feat: add recalculate_handicap RPC"
```

---

## Task 6: TypeScript Types

**Files:**
- Modify: `src/types.ts`

- [ ] **Step 1: Add new types to `src/types.ts`**

Append after the existing `Friendship` type (line 72):

```typescript
export type ScorecardStatus = 'draft' | 'final';

export type Scorecard = {
  id: string;
  roundId: string;
  playerId: string;
  enteredBy: string;
  status: ScorecardStatus;
  holes: 9 | 18;
  grossScore: number | null;
  netScore: number | null;
  handicapIndexAtRound: number | null;
  courseHandicap: number | null;
  playingHandicap: number | null;
  courseName: string | null;
  teeName: string | null;
  teeColor: string | null;
  courseRating: number | null;
  slopeRating: number | null;
  par: number | null;
  startedAt: string | null;
  completedAt: string | null;
  playerName?: string | null;
  playerHandle?: string | null;
};

export type ScorecardHole = {
  id: string;
  scorecardId: string;
  holeNumber: number;
  par: number | null;
  strokeIndex: number | null;
  yards: number | null;
  strokes: number | null;
  putts: number | null;
  fairwayHit: boolean | null;
  gir: boolean | null;
  penalties: number;
};

export type HandicapProfile = {
  userId: string;
  handicapIndex: number | null;
  handicapSource: string;
  lastCalculatedAt: string | null;
  isHidden: boolean;
};

export type HandicapDifferential = {
  id: string;
  userId: string;
  roundId: string | null;
  scorecardId: string;
  holes: 9 | 18;
  adjustedGrossScore: number;
  courseRating: number;
  slopeRating: number;
  pcc: number;
  differential: number;
  playedAt: string;
};
```

- [ ] **Step 2: Commit**

```bash
git add src/types.ts
git commit -m "feat: add Scorecard, ScorecardHole, HandicapProfile, HandicapDifferential types"
```

---

## Task 7: Database Type Definitions

**Files:**
- Modify: `src/lib/supabase.ts`

- [ ] **Step 1: Add new table and function types to `Database`**

Add the following entries inside `public.Tables` (after the `push_tokens` entry, before the closing `};` of Tables):

```typescript
      scorecards: {
        Row: {
          id: string;
          round_id: string;
          player_id: string;
          entered_by: string;
          status: string;
          holes: number;
          gross_score: number | null;
          net_score: number | null;
          handicap_index_at_round: number | null;
          course_handicap: number | null;
          playing_handicap: number | null;
          course_name: string | null;
          tee_name: string | null;
          tee_color: string | null;
          course_rating: number | null;
          slope_rating: number | null;
          par: number | null;
          started_at: string | null;
          completed_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          round_id: string;
          player_id: string;
          entered_by: string;
          status?: string;
          holes: number;
          gross_score?: number | null;
          net_score?: number | null;
          handicap_index_at_round?: number | null;
          course_handicap?: number | null;
          playing_handicap?: number | null;
          course_name?: string | null;
          tee_name?: string | null;
          tee_color?: string | null;
          course_rating?: number | null;
          slope_rating?: number | null;
          par?: number | null;
          started_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          round_id?: string;
          player_id?: string;
          entered_by?: string;
          status?: string;
          holes?: number;
          gross_score?: number | null;
          net_score?: number | null;
          handicap_index_at_round?: number | null;
          course_handicap?: number | null;
          playing_handicap?: number | null;
          course_name?: string | null;
          tee_name?: string | null;
          tee_color?: string | null;
          course_rating?: number | null;
          slope_rating?: number | null;
          par?: number | null;
          started_at?: string | null;
          completed_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
      };
      scorecard_holes: {
        Row: {
          id: string;
          scorecard_id: string;
          hole_number: number;
          par: number | null;
          stroke_index: number | null;
          yards: number | null;
          strokes: number | null;
          putts: number | null;
          fairway_hit: boolean | null;
          gir: boolean | null;
          penalties: number;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          scorecard_id: string;
          hole_number: number;
          par?: number | null;
          stroke_index?: number | null;
          yards?: number | null;
          strokes?: number | null;
          putts?: number | null;
          fairway_hit?: boolean | null;
          gir?: boolean | null;
          penalties?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          scorecard_id?: string;
          hole_number?: number;
          par?: number | null;
          stroke_index?: number | null;
          yards?: number | null;
          strokes?: number | null;
          putts?: number | null;
          fairway_hit?: boolean | null;
          gir?: boolean | null;
          penalties?: number;
          created_at?: string;
          updated_at?: string;
        };
      };
      player_handicap_profiles: {
        Row: {
          user_id: string;
          handicap_index: number | null;
          handicap_source: string;
          last_calculated_at: string | null;
          is_hidden: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          user_id: string;
          handicap_index?: number | null;
          handicap_source?: string;
          last_calculated_at?: string | null;
          is_hidden?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          user_id?: string;
          handicap_index?: number | null;
          handicap_source?: string;
          last_calculated_at?: string | null;
          is_hidden?: boolean;
          created_at?: string;
          updated_at?: string;
        };
      };
      handicap_differentials: {
        Row: {
          id: string;
          user_id: string;
          round_id: string | null;
          scorecard_id: string;
          holes: number;
          adjusted_gross_score: number;
          course_rating: number;
          slope_rating: number;
          pcc: number;
          differential: number;
          played_at: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          round_id?: string | null;
          scorecard_id: string;
          holes: number;
          adjusted_gross_score: number;
          course_rating: number;
          slope_rating: number;
          pcc?: number;
          differential: number;
          played_at: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          round_id?: string | null;
          scorecard_id?: string;
          holes?: number;
          adjusted_gross_score?: number;
          course_rating?: number;
          slope_rating?: number;
          pcc?: number;
          differential?: number;
          played_at?: string;
          created_at?: string;
        };
      };
```

Add the following entry inside `public.Functions` (after the `delete_round` entry):

```typescript
      recalculate_handicap: {
        Args: { p_user_id: string };
        Returns: number | null;
      };
```

- [ ] **Step 2: Commit**

```bash
git add src/lib/supabase.ts
git commit -m "feat: add Database type definitions for scorecard and handicap tables"
```

---

## Task 8: Navigation — Add RoundScore Route

**Files:**
- Modify: `src/navigation/types.ts`
- Modify: `src/navigation/AppNavigator.tsx`

- [ ] **Step 1: Add route to `src/navigation/types.ts`**

Add inside `RootStackParamList` (after the `Username` line):

```typescript
  RoundScore: { roundId: string; playerId: string; holes: 9 | 18; courseName: string };
```

- [ ] **Step 2: Register screen in `src/navigation/AppNavigator.tsx`**

Add import at top:

```typescript
import { RoundScoreScreen } from '../screens/RoundScoreScreen';
```

Add inside the authenticated `<Stack.Group>` (after the Username screen):

```typescript
            <Stack.Screen name="RoundScore" component={RoundScoreScreen} />
```

- [ ] **Step 3: Commit**

```bash
git add src/navigation/types.ts src/navigation/AppNavigator.tsx
git commit -m "feat: add RoundScore route and screen registration"
```

---

## Task 9: DataContext — Scorecard Mutations

**Files:**
- Modify: `src/context/DataContext.tsx`

- [ ] **Step 1: Add scorecard mutations to DataContext**

Add to the `DataContextValue` type:

```typescript
  createScorecard: (roundId: string, playerId: string, holes: 9 | 18, courseName: string) => Promise<string | null>;
  saveHoleScores: (scorecardId: string, holes: { holeNumber: number; strokes: number; par: number | null }[]) => Promise<boolean>;
  finalizeScorecard: (scorecardId: string, grossScore: number, courseRating: number | null, slopeRating: number | null, par: number | null) => Promise<boolean>;
```

Add the three `useCallback` implementations before the `value` declaration:

```typescript
  const createScorecard = useCallback(
    async (roundId: string, playerId: string, holes: 9 | 18, courseName: string): Promise<string | null> => {
      if (!user) return null;

      const { data, error } = await supabase
        .from('scorecards')
        .upsert(
          {
            round_id: roundId,
            player_id: playerId,
            entered_by: user.id,
            holes,
            course_name: courseName,
            status: 'draft',
          },
          { onConflict: 'round_id,player_id' }
        )
        .select('id')
        .maybeSingle();

      if (error || !data) return null;
      return data.id;
    },
    [user],
  );

  const saveHoleScores = useCallback(
    async (
      scorecardId: string,
      holes: { holeNumber: number; strokes: number; par: number | null }[],
    ): Promise<boolean> => {
      if (!user) return false;

      const rows = holes.map((h) => ({
        scorecard_id: scorecardId,
        hole_number: h.holeNumber,
        strokes: h.strokes,
        par: h.par,
      }));

      const { error } = await supabase
        .from('scorecard_holes')
        .upsert(rows, { onConflict: 'scorecard_id,hole_number' });

      return !error;
    },
    [user],
  );

  const finalizeScorecard = useCallback(
    async (
      scorecardId: string,
      grossScore: number,
      courseRating: number | null,
      slopeRating: number | null,
      par: number | null,
    ): Promise<boolean> => {
      if (!user) return false;

      // Update scorecard to final
      const { data: card, error: updateError } = await supabase
        .from('scorecards')
        .update({
          gross_score: grossScore,
          status: 'final',
          course_rating: courseRating,
          slope_rating: slopeRating,
          par,
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', scorecardId)
        .select('id, round_id, player_id, holes')
        .maybeSingle();

      if (updateError || !card) return false;

      // If course rating and slope are provided, create a handicap differential
      if (courseRating != null && slopeRating != null) {
        const differential = Number(
          ((113 / slopeRating) * (grossScore - courseRating)).toFixed(2)
        );

        await supabase.from('handicap_differentials').insert({
          user_id: card.player_id,
          round_id: card.round_id,
          scorecard_id: card.id,
          holes: card.holes,
          adjusted_gross_score: grossScore,
          course_rating: courseRating,
          slope_rating: slopeRating,
          differential,
          played_at: new Date().toISOString(),
        });

        // Recalculate handicap
        await supabase.rpc('recalculate_handicap', { p_user_id: card.player_id });
      }

      return true;
    },
    [user],
  );
```

Add the three new functions to the `value` object:

```typescript
  const value: DataContextValue = {
    createRound,
    respondToRound,
    inviteFriendToRound,
    deleteRound,
    createScorecard,
    saveHoleScores,
    finalizeScorecard,
  };
```

- [ ] **Step 2: Commit**

```bash
git add src/context/DataContext.tsx
git commit -m "feat: add scorecard mutations to DataContext"
```

---

## Task 10: useScorecards Hook

**Files:**
- Create: `src/hooks/useScorecards.ts`

- [ ] **Step 1: Write the hook**

```typescript
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Scorecard } from '../types';
import { withSupabaseRetry } from '../utils/retry';

type ScorecardRow = {
  id: string;
  round_id: string;
  player_id: string;
  entered_by: string;
  status: string;
  holes: number;
  gross_score: number | null;
  net_score: number | null;
  handicap_index_at_round: number | null;
  course_handicap: number | null;
  playing_handicap: number | null;
  course_name: string | null;
  tee_name: string | null;
  tee_color: string | null;
  course_rating: number | null;
  slope_rating: number | null;
  par: number | null;
  started_at: string | null;
  completed_at: string | null;
  profile: {
    id: string;
    full_name: string | null;
    username: string | null;
  } | null;
};

const mapRow = (row: ScorecardRow): Scorecard => ({
  id: row.id,
  roundId: row.round_id,
  playerId: row.player_id,
  enteredBy: row.entered_by,
  status: row.status === 'final' ? 'final' : 'draft',
  holes: row.holes === 9 ? 9 : 18,
  grossScore: row.gross_score,
  netScore: row.net_score,
  handicapIndexAtRound: row.handicap_index_at_round,
  courseHandicap: row.course_handicap,
  playingHandicap: row.playing_handicap,
  courseName: row.course_name,
  teeName: row.tee_name,
  teeColor: row.tee_color,
  courseRating: row.course_rating,
  slopeRating: row.slope_rating,
  par: row.par,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  playerName: row.profile?.full_name ?? null,
  playerHandle: row.profile?.username ? `@${row.profile.username}` : null,
});

export const useScorecards = (roundId?: string) => {
  const [scorecards, setScorecards] = useState<Scorecard[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchScorecards = useCallback(async () => {
    if (!roundId) {
      setScorecards([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const result = await withSupabaseRetry(() =>
        supabase
          .from('scorecards')
          .select(
            `
              id, round_id, player_id, entered_by, status, holes,
              gross_score, net_score, handicap_index_at_round,
              course_handicap, playing_handicap, course_name,
              tee_name, tee_color, course_rating, slope_rating, par,
              started_at, completed_at,
              profile:profiles!scorecards_player_id_fkey (
                id, full_name, username
              )
            `,
          )
          .eq('round_id', roundId)
      );

      if (result.error) {
        setError(result.didRetry ? 'Connection failed after retries' : 'Failed to load scorecards');
        setScorecards([]);
        return;
      }

      const mapped = (result.data as unknown as ScorecardRow[]).map(mapRow);
      setScorecards(mapped);
    } catch {
      setError('Unexpected error loading scorecards');
      setScorecards([]);
    } finally {
      setLoading(false);
    }
  }, [roundId]);

  useEffect(() => {
    fetchScorecards();
  }, [fetchScorecards]);

  useEffect(() => {
    if (!roundId) return;
    const channel = supabase
      .channel(`scorecards-${roundId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'scorecards', filter: `round_id=eq.${roundId}` },
        () => fetchScorecards(),
      );

    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roundId, fetchScorecards]);

  return { scorecards, loading, error, refresh: fetchScorecards };
};
```

- [ ] **Step 2: Commit**

```bash
git add src/hooks/useScorecards.ts
git commit -m "feat: add useScorecards hook"
```

---

## Task 11: useHandicap Hook

**Files:**
- Create: `src/hooks/useHandicap.ts`

- [ ] **Step 1: Write the hook**

```typescript
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { HandicapProfile, HandicapDifferential } from '../types';
import { useAuth } from '../context/AuthContext';
import { withSupabaseRetry } from '../utils/retry';

export const useHandicap = (userId?: string) => {
  const { user } = useAuth();
  const targetId = userId ?? user?.id;

  const [profile, setProfile] = useState<HandicapProfile | null>(null);
  const [differentials, setDifferentials] = useState<HandicapDifferential[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchHandicap = useCallback(async () => {
    if (!targetId) {
      setProfile(null);
      setDifferentials([]);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // Fetch profile and differentials in parallel
      const [profileResult, diffResult] = await Promise.all([
        withSupabaseRetry(() =>
          supabase
            .from('player_handicap_profiles')
            .select('user_id, handicap_index, handicap_source, last_calculated_at, is_hidden')
            .eq('user_id', targetId)
            .maybeSingle()
        ),
        withSupabaseRetry(() =>
          supabase
            .from('handicap_differentials')
            .select('id, user_id, round_id, scorecard_id, holes, adjusted_gross_score, course_rating, slope_rating, pcc, differential, played_at')
            .eq('user_id', targetId)
            .order('played_at', { ascending: false })
            .limit(20)
        ),
      ]);

      if (profileResult.data) {
        const row = profileResult.data;
        setProfile({
          userId: row.user_id,
          handicapIndex: row.handicap_index,
          handicapSource: row.handicap_source,
          lastCalculatedAt: row.last_calculated_at,
          isHidden: row.is_hidden,
        });
      } else {
        setProfile(null);
      }

      if (diffResult.data) {
        setDifferentials(
          (diffResult.data as any[]).map((d) => ({
            id: d.id,
            userId: d.user_id,
            roundId: d.round_id,
            scorecardId: d.scorecard_id,
            holes: d.holes === 9 ? 9 : 18,
            adjustedGrossScore: d.adjusted_gross_score,
            courseRating: d.course_rating,
            slopeRating: d.slope_rating,
            pcc: d.pcc,
            differential: d.differential,
            playedAt: d.played_at,
          }))
        );
      } else {
        setDifferentials([]);
      }

      if (profileResult.error && diffResult.error) {
        setError('Failed to load handicap data');
      }
    } catch {
      setError('Unexpected error loading handicap');
    } finally {
      setLoading(false);
    }
  }, [targetId]);

  useEffect(() => {
    fetchHandicap();
  }, [fetchHandicap]);

  return { profile, differentials, loading, error, refresh: fetchHandicap };
};
```

- [ ] **Step 2: Commit**

```bash
git add src/hooks/useHandicap.ts
git commit -m "feat: add useHandicap hook"
```

---

## Task 12: RoundScoreScreen

**Files:**
- Create: `src/screens/RoundScoreScreen.tsx`

- [ ] **Step 1: Build the score entry screen**

This screen supports two modes: total-score-only (quick) and hole-by-hole entry. The user picks their entry mode, enters scores, then finalizes. Optionally enters course rating / slope for handicap tracking.

```typescript
import React, { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { BackButton } from '../components/BackButton';
import { PrimaryButton } from '../components/PrimaryButton';
import { colors, radii, spacing, typography } from '../theme';
import { RootStackParamList } from '../navigation/types';
import { useData } from '../context/DataContext';
import { useAuth } from '../context/AuthContext';

type Props = NativeStackScreenProps<RootStackParamList, 'RoundScore'>;

type HoleEntry = {
  holeNumber: number;
  strokes: string;
  par: string;
};

export const RoundScoreScreen: React.FC<Props> = ({ navigation, route }) => {
  const { roundId, playerId, holes, courseName } = route.params;
  const { user } = useAuth();
  const { createScorecard, saveHoleScores, finalizeScorecard } = useData();

  const [mode, setMode] = useState<'total' | 'holes' | null>(null);
  const [totalScore, setTotalScore] = useState('');
  const [courseRating, setCourseRating] = useState('');
  const [slopeRating, setSlopeRating] = useState('');
  const [par, setPar] = useState(holes === 9 ? '36' : '72');
  const [holeEntries, setHoleEntries] = useState<HoleEntry[]>(() =>
    Array.from({ length: holes }, (_, i) => ({
      holeNumber: i + 1,
      strokes: '',
      par: '',
    })),
  );
  const [saving, setSaving] = useState(false);

  const holesTotal = holeEntries.reduce((sum, h) => {
    const n = parseInt(h.strokes, 10);
    return sum + (isNaN(n) ? 0 : n);
  }, 0);

  const handleHoleChange = useCallback(
    (index: number, field: 'strokes' | 'par', value: string) => {
      setHoleEntries((prev) => {
        const next = [...prev];
        next[index] = { ...next[index], [field]: value };
        return next;
      });
    },
    [],
  );

  const handleSave = async () => {
    if (!user) return;

    const gross = mode === 'total' ? parseInt(totalScore, 10) : holesTotal;
    if (isNaN(gross) || gross < 1) {
      Alert.alert('Invalid score', 'Please enter a valid total score.');
      return;
    }

    setSaving(true);

    const scorecardId = await createScorecard(roundId, playerId, holes, courseName);
    if (!scorecardId) {
      Alert.alert('Error', 'Could not create scorecard. Please try again.');
      setSaving(false);
      return;
    }

    // Save hole-by-hole scores if in holes mode
    if (mode === 'holes') {
      const holeData = holeEntries
        .filter((h) => h.strokes !== '')
        .map((h) => ({
          holeNumber: h.holeNumber,
          strokes: parseInt(h.strokes, 10),
          par: h.par ? parseInt(h.par, 10) : null,
        }));

      if (holeData.length > 0) {
        const saved = await saveHoleScores(scorecardId, holeData);
        if (!saved) {
          Alert.alert('Error', 'Could not save hole scores. Please try again.');
          setSaving(false);
          return;
        }
      }
    }

    const cr = courseRating ? parseFloat(courseRating) : null;
    const sr = slopeRating ? parseInt(slopeRating, 10) : null;
    const p = par ? parseInt(par, 10) : null;

    const finalized = await finalizeScorecard(scorecardId, gross, cr, sr, p);
    setSaving(false);

    if (finalized) {
      navigation.goBack();
    } else {
      Alert.alert('Error', 'Could not finalize scorecard. Please try again.');
    }
  };

  if (!mode) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.container}>
          <BackButton onPress={() => navigation.goBack()} />
          <Text style={styles.title}>Enter Score</Text>
          <Text style={styles.subtitle}>{courseName} · {holes} holes</Text>

          <View style={styles.modeSection}>
            <Text style={styles.sectionTitle}>How would you like to enter your score?</Text>

            <Pressable style={styles.modeCard} onPress={() => setMode('total')}>
              <Text style={styles.modeCardTitle}>Total Score</Text>
              <Text style={styles.modeCardDesc}>Just enter your final score</Text>
            </Pressable>

            <Pressable style={styles.modeCard} onPress={() => setMode('holes')}>
              <Text style={styles.modeCardTitle}>Hole by Hole</Text>
              <Text style={styles.modeCardDesc}>Enter strokes for each hole</Text>
            </Pressable>
          </View>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView contentContainerStyle={styles.container}>
          <BackButton onPress={() => (mode ? setMode(null) : navigation.goBack())} />
          <Text style={styles.title}>
            {mode === 'total' ? 'Total Score' : 'Hole by Hole'}
          </Text>
          <Text style={styles.subtitle}>{courseName} · {holes} holes</Text>

          {mode === 'total' && (
            <View style={styles.inputSection}>
              <Text style={styles.inputLabel}>Gross Score</Text>
              <TextInput
                style={styles.scoreInput}
                value={totalScore}
                onChangeText={setTotalScore}
                keyboardType="number-pad"
                placeholder={holes === 9 ? 'e.g. 45' : 'e.g. 90'}
                placeholderTextColor={colors.placeholder}
                maxLength={3}
              />
            </View>
          )}

          {mode === 'holes' && (
            <View style={styles.holesSection}>
              <View style={styles.holesHeader}>
                <Text style={[styles.holesHeaderText, { flex: 1 }]}>Hole</Text>
                <Text style={[styles.holesHeaderText, { width: 64 }]}>Par</Text>
                <Text style={[styles.holesHeaderText, { width: 64 }]}>Score</Text>
              </View>
              {holeEntries.map((entry, i) => (
                <View key={entry.holeNumber} style={styles.holeRow}>
                  <Text style={[styles.holeNumber, { flex: 1 }]}>{entry.holeNumber}</Text>
                  <TextInput
                    style={[styles.holeInput, { width: 64 }]}
                    value={entry.par}
                    onChangeText={(v) => handleHoleChange(i, 'par', v)}
                    keyboardType="number-pad"
                    placeholder="-"
                    placeholderTextColor={colors.placeholder}
                    maxLength={1}
                  />
                  <TextInput
                    style={[styles.holeInput, { width: 64 }]}
                    value={entry.strokes}
                    onChangeText={(v) => handleHoleChange(i, 'strokes', v)}
                    keyboardType="number-pad"
                    placeholder="-"
                    placeholderTextColor={colors.placeholder}
                    maxLength={2}
                  />
                </View>
              ))}
              <View style={styles.holesTotalRow}>
                <Text style={[styles.holesTotalLabel, { flex: 1 }]}>Total</Text>
                <Text style={[styles.holesTotalValue, { width: 64 }]} />
                <Text style={[styles.holesTotalValue, { width: 64 }]}>{holesTotal || '-'}</Text>
              </View>
            </View>
          )}

          <View style={styles.divider} />

          <Text style={styles.sectionTitle}>Course Details (optional, for handicap)</Text>

          <View style={styles.courseRow}>
            <View style={styles.courseField}>
              <Text style={styles.inputLabel}>Course Rating</Text>
              <TextInput
                style={styles.courseInput}
                value={courseRating}
                onChangeText={setCourseRating}
                keyboardType="decimal-pad"
                placeholder="72.0"
                placeholderTextColor={colors.placeholder}
                maxLength={5}
              />
            </View>
            <View style={styles.courseField}>
              <Text style={styles.inputLabel}>Slope Rating</Text>
              <TextInput
                style={styles.courseInput}
                value={slopeRating}
                onChangeText={setSlopeRating}
                keyboardType="number-pad"
                placeholder="113"
                placeholderTextColor={colors.placeholder}
                maxLength={3}
              />
            </View>
            <View style={styles.courseField}>
              <Text style={styles.inputLabel}>Par</Text>
              <TextInput
                style={styles.courseInput}
                value={par}
                onChangeText={setPar}
                keyboardType="number-pad"
                placeholder="72"
                placeholderTextColor={colors.placeholder}
                maxLength={3}
              />
            </View>
          </View>

          {saving ? (
            <ActivityIndicator size="large" color={colors.accent} style={{ marginTop: spacing.lg }} />
          ) : (
            <PrimaryButton
              label="Save Score"
              onPress={handleSave}
              style={{ marginTop: spacing.lg }}
            />
          )}
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    padding: spacing.lg,
    gap: spacing.md,
  },
  title: {
    fontSize: typography.title,
    fontWeight: '700',
    color: colors.text,
  },
  subtitle: {
    fontSize: typography.body,
    color: colors.muted,
  },
  sectionTitle: {
    fontSize: typography.subtitle,
    fontWeight: '600',
    color: colors.text,
  },
  modeSection: {
    gap: spacing.md,
    marginTop: spacing.md,
  },
  modeCard: {
    backgroundColor: colors.card,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
    gap: spacing.xs / 2,
  },
  modeCardTitle: {
    fontSize: typography.subtitle,
    fontWeight: '700',
    color: colors.text,
  },
  modeCardDesc: {
    fontSize: typography.small,
    color: colors.muted,
  },
  inputSection: {
    gap: spacing.xs,
  },
  inputLabel: {
    fontSize: typography.small,
    fontWeight: '600',
    color: colors.muted,
  },
  scoreInput: {
    backgroundColor: colors.card,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.md,
    fontSize: 28,
    fontWeight: '700',
    color: colors.text,
    textAlign: 'center',
  },
  holesSection: {
    backgroundColor: colors.card,
    borderRadius: radii.md,
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  holesHeader: {
    flexDirection: 'row',
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.surfaceGreen,
    borderBottomWidth: 1,
    borderColor: colors.border,
  },
  holesHeaderText: {
    fontSize: typography.small,
    fontWeight: '700',
    color: colors.textSecondary,
    textAlign: 'center',
  },
  holeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.md,
    borderBottomWidth: 1,
    borderColor: colors.borderLight,
  },
  holeNumber: {
    fontSize: typography.body,
    fontWeight: '600',
    color: colors.text,
  },
  holeInput: {
    textAlign: 'center',
    fontSize: typography.body,
    fontWeight: '600',
    color: colors.text,
    paddingVertical: spacing.xs,
  },
  holesTotalRow: {
    flexDirection: 'row',
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.surfaceGreen,
  },
  holesTotalLabel: {
    fontSize: typography.body,
    fontWeight: '700',
    color: colors.text,
  },
  holesTotalValue: {
    fontSize: typography.body,
    fontWeight: '700',
    color: colors.secondary,
    textAlign: 'center',
  },
  divider: {
    height: 1,
    backgroundColor: colors.border,
    marginVertical: spacing.xs,
  },
  courseRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  courseField: {
    flex: 1,
    gap: spacing.xs / 2,
  },
  courseInput: {
    backgroundColor: colors.card,
    borderRadius: radii.sm,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.sm,
    fontSize: typography.body,
    fontWeight: '600',
    color: colors.text,
    textAlign: 'center',
  },
});
```

- [ ] **Step 2: Commit**

```bash
git add src/screens/RoundScoreScreen.tsx
git commit -m "feat: add RoundScoreScreen for score entry"
```

---

## Task 13: RoundDetailScreen — Scorecard Summary + Enter Scores Button

**Files:**
- Modify: `src/screens/RoundDetailScreen.tsx`

- [ ] **Step 1: Add scorecard section to RoundDetailScreen**

Add imports at top of file:

```typescript
import { useScorecards } from '../hooks/useScorecards';
```

Inside the component, after the existing `useData()` call, add:

```typescript
  const { scorecards } = useScorecards(route.params.roundId);
```

Insert the following JSX after the "Invite friends" `PrimaryButton` (before the `{isCreator && (` delete block), inside the ScrollView:

```tsx
        {/* Scorecards section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle} numberOfLines={1}>
            Scorecards
          </Text>
          {scorecards.length === 0 ? (
            <Text style={styles.helperText} numberOfLines={1}>
              No scores entered yet.
            </Text>
          ) : (
            scorecards.map((sc) => (
              <View key={sc.id} style={styles.scorecardRow}>
                <View style={styles.playerInfo}>
                  <Text style={styles.playerName} numberOfLines={1} ellipsizeMode="tail">
                    {sc.playerName || sc.playerHandle || 'Player'}
                  </Text>
                  {sc.playerHandle && sc.playerName && (
                    <Text style={styles.playerHandle} numberOfLines={1} ellipsizeMode="tail">
                      {sc.playerHandle}
                    </Text>
                  )}
                </View>
                <View style={styles.scoreInfo}>
                  {sc.grossScore != null ? (
                    <Text style={styles.scoreValue}>{sc.grossScore}</Text>
                  ) : (
                    <Text style={styles.scorePending}>—</Text>
                  )}
                  <View style={[styles.statusPill, sc.status === 'final' ? { backgroundColor: 'rgba(124, 203, 138, 0.15)', borderColor: colors.primary } : { backgroundColor: 'rgba(107, 114, 128, 0.1)', borderColor: colors.border }]}>
                    <Text style={[styles.statusText, sc.status === 'final' ? { color: colors.secondary } : { color: colors.muted }]} numberOfLines={1}>
                      {sc.status === 'final' ? 'Final' : 'Draft'}
                    </Text>
                  </View>
                </View>
              </View>
            ))
          )}
        </View>

        {user && !round.locked && (
          <PrimaryButton
            label="Enter Scores"
            variant="secondary"
            onPress={() =>
              navigation.navigate('RoundScore', {
                roundId: round.id,
                playerId: user.id,
                holes: round.holes,
                courseName: round.course,
              })
            }
          />
        )}
```

Add these additional styles to the StyleSheet:

```typescript
  scorecardRow: {
    paddingVertical: spacing.sm,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderColor: colors.border,
    minWidth: 0,
    gap: spacing.sm,
  },
  scoreInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    flexShrink: 0,
  },
  scoreValue: {
    fontSize: typography.subtitle,
    fontWeight: '700',
    color: colors.text,
  },
  scorePending: {
    fontSize: typography.subtitle,
    fontWeight: '600',
    color: colors.muted,
  },
```

- [ ] **Step 2: Commit**

```bash
git add src/screens/RoundDetailScreen.tsx
git commit -m "feat: add scorecard summary and Enter Scores button to RoundDetailScreen"
```

---

## Task 14: ProfileScreen — Handicap Display

**Files:**
- Modify: `src/screens/ProfileScreen.tsx`

- [ ] **Step 1: Add handicap display to ProfileScreen**

Add import at top of file:

```typescript
import { useHandicap } from '../hooks/useHandicap';
```

Inside the component, after the existing `useFriendships()` call, add:

```typescript
  const { profile: handicapProfile } = useHandicap();
```

Insert the following JSX inside the stats row (after the existing Friends stat card, before the closing `</View>` of `statsRow`):

```tsx
              <View style={styles.statCard}>
                <Text style={styles.statNumber}>
                  {handicapProfile?.handicapIndex != null
                    ? handicapProfile.handicapIndex.toFixed(1)
                    : '—'}
                </Text>
                <Text style={styles.statLabel}>Handicap</Text>
              </View>
```

- [ ] **Step 2: Commit**

```bash
git add src/screens/ProfileScreen.tsx
git commit -m "feat: add handicap display to ProfileScreen"
```

---

## Summary

**14 tasks** total. After all tasks are complete:

- 4 new Supabase tables with RLS
- 1 RPC for handicap recalculation  
- 4 new TypeScript domain types
- 2 new hooks (`useScorecards`, `useHandicap`)
- 1 new screen (`RoundScoreScreen`) with total + hole-by-hole entry
- RoundDetail shows scorecard summary + "Enter Scores" button
- Profile shows current handicap index
- Full handicap differential pipeline: enter score → compute differential → recalculate index

The core loop is complete: schedule round → play → enter score → handicap updates → compare with friends.
