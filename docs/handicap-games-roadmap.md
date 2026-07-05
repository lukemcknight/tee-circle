# TeeCircle Handicap, Matches, and Wagers Roadmap

## Goal

Add four connected capabilities to TeeCircle:

1. Handicap tracking
2. Score entry after each round
3. Handicap-based games and wagers with friends
4. Social leaderboard across players, matches, and seasons

This plan is designed for the current Expo + Supabase app and fits the existing structure:

- `rounds` already handles tee times and participation
- `friendships` already handles the social graph
- `RoundDetailScreen` is the natural place to attach scorecards and match summaries

## Product Scope Recommendation

Build this in 4 releases.

### Release 1: Scores + Handicap Foundation

- Let players enter total score and optional hole-by-hole scores for a round
- Track course metadata needed for handicap calculations
- Show handicap history and current handicap in profile
- Support 9-hole and 18-hole rounds

### Release 2: Single-Round Matches

- Create a match tied to one round
- Support handicap-based net stroke play and match play
- Support fixed wager amounts
- Show live standings inside the round detail view

### Release 3: Multi-Round Series

- Create a series with multiple rounds
- Aggregate standings across all included rounds
- Support team formats

### Release 4: Leaderboards + Expanded Games

- Season leaderboard
- Friends-only leaderboard
- Money won/lost leaderboard
- Additional formats like Nassau and skins

## Recommended First Ruleset

Start with the smallest ruleset that is still compelling:

- Handicap model: TeeCircle in-app handicap
- Money handling: tracking only, no payments
- First games:
  - Net stroke play
  - Match play
  - Nassau
- Match scopes:
  - Single-round match
  - Multi-round series

Do not start with GHIN/USGA integration, payment processing, or complex games like Wolf. Those add legal, API, and rules complexity before the core gameplay loop is proven.

## Proposed Data Model

Keep scheduling and competition separate. `rounds` should remain the scheduling object. Add score and match tables around it.

### 1. Handicap Tables

#### `player_handicap_profiles`

One row per user.

Suggested columns:

- `user_id uuid primary key references auth.users(id)`
- `handicap_index numeric(4,1) null`
- `handicap_source text not null default 'teecircle'`
- `last_calculated_at timestamptz null`
- `is_hidden boolean not null default false`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Purpose:

- Stores the player’s current in-app handicap
- Allows future support for external handicap sources

#### `handicap_differentials`

One row per score posted toward handicap.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references auth.users(id)`
- `round_id uuid null references public.rounds(id) on delete set null`
- `scorecard_id uuid not null`
- `holes integer not null check (holes in (9,18))`
- `adjusted_gross_score integer not null`
- `course_rating numeric(4,1) not null`
- `slope_rating integer not null`
- `pcc integer not null default 0`
- `differential numeric(5,2) not null`
- `played_at timestamptz not null`
- `created_at timestamptz not null default now()`

Purpose:

- Preserves the exact values used to compute handicap history
- Makes recalculation auditable

### 2. Score Tables

#### `scorecards`

One row per player per round.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `round_id uuid not null references public.rounds(id) on delete cascade`
- `player_id uuid not null references auth.users(id)`
- `entered_by uuid not null references auth.users(id)`
- `status text not null default 'draft'`
- `holes integer not null check (holes in (9,18))`
- `gross_score integer null`
- `net_score integer null`
- `handicap_index_at_round numeric(4,1) null`
- `course_handicap integer null`
- `playing_handicap integer null`
- `course_name text null`
- `tee_name text null`
- `tee_color text null`
- `course_rating numeric(4,1) null`
- `slope_rating integer null`
- `par integer null`
- `started_at timestamptz null`
- `completed_at timestamptz null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraints:

- unique `(round_id, player_id)`

Purpose:

- Stores the player’s round-level scoring snapshot
- Freezes handicap values used for that round so later handicap changes do not rewrite history

#### `scorecard_holes`

One row per hole per scorecard.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `scorecard_id uuid not null references public.scorecards(id) on delete cascade`
- `hole_number integer not null`
- `par integer null`
- `stroke_index integer null`
- `yards integer null`
- `strokes integer null`
- `putts integer null`
- `fairway_hit boolean null`
- `gir boolean null`
- `penalties integer null default 0`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraints:

- unique `(scorecard_id, hole_number)`

Purpose:

- Supports simple total-score entry now and richer stats later

### 3. Match and Series Tables

#### `match_series`

Optional parent object for multi-round competitions.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `created_by uuid not null references auth.users(id)`
- `name text not null`
- `format text not null`
- `status text not null default 'open'`
- `handicap_mode text not null default 'net'`
- `rounds_count integer not null default 0`
- `starts_at timestamptz null`
- `ends_at timestamptz null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

#### `matches`

Competition object for either a single round or a series leg.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `round_id uuid null references public.rounds(id) on delete cascade`
- `series_id uuid null references public.match_series(id) on delete cascade`
- `created_by uuid not null references auth.users(id)`
- `name text not null`
- `format text not null`
- `status text not null default 'open'`
- `handicap_mode text not null default 'net'`
- `scoring_mode text not null`
- `wager_type text null`
- `wager_amount numeric(10,2) null`
- `carryovers_enabled boolean not null default false`
- `auto_settle boolean not null default true`
- `starts_on_hole integer not null default 1`
- `holes integer not null check (holes in (9,18))`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Notes:

- `round_id` present for single-round matches
- `series_id` present for multi-round grouping

#### `match_participants`

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `match_id uuid not null references public.matches(id) on delete cascade`
- `player_id uuid not null references auth.users(id)`
- `team_number integer null`
- `handicap_index_snapshot numeric(4,1) null`
- `course_handicap_snapshot integer null`
- `strokes_allocated integer null`
- `is_active boolean not null default true`
- `created_at timestamptz not null default now()`

Constraints:

- unique `(match_id, player_id)`

Purpose:

- Freezes the exact handicap setup used for the match

#### `match_results`

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `match_id uuid not null references public.matches(id) on delete cascade`
- `player_id uuid not null references auth.users(id)`
- `gross_total integer null`
- `net_total integer null`
- `points numeric(8,2) null`
- `money_delta numeric(10,2) null`
- `result text null`
- `summary jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Purpose:

- Stores resolved results after scoring is complete
- Avoids recalculating standings for every read

### 4. Wager Tracking

#### `wagers`

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `match_id uuid not null references public.matches(id) on delete cascade`
- `created_by uuid not null references auth.users(id)`
- `name text not null`
- `amount numeric(10,2) not null`
- `status text not null default 'open'`
- `settlement_method text not null default 'manual'`
- `notes text null`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

#### `wager_entries`

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `wager_id uuid not null references public.wagers(id) on delete cascade`
- `player_id uuid not null references auth.users(id)`
- `amount_delta numeric(10,2) null`
- `result text null`
- `created_at timestamptz not null default now()`

Purpose:

- Lets one wager be settled across several players

## Views and Derived Data

Do not make leaderboard tables first. Use views and only materialize if needed later.

### `leaderboard_friend_totals`

Aggregate by player for a given friendship network:

- rounds played
- handicap trend
- match wins
- net average
- money won/lost
- streak

### `round_match_standings`

Resolve one round’s live standings:

- gross score
- net score
- allocated strokes
- current position

### `series_standings`

Aggregate all matches in one series:

- total points
- matches won
- cumulative net

## RLS Strategy

This is the critical part. The feature is feasible if the security model is clean.

Use these rules:

### Scorecards

- A player can view their own scorecards
- A round creator can view scorecards for that round
- A confirmed participant in the round can view all scorecards for that round
- Only the player or the round creator can edit that player’s scorecard
- Only match participants can see scorecards used in their match

### Handicap

- A user can always view their own handicap profile
- Accepted friends can view each other’s handicap profile unless `is_hidden = true`
- Only the user can edit their handicap profile
- Handicap differentials are readable by the user and optionally by friends

### Matches and Wagers

- Only participants can view a match
- Only the match creator can edit match configuration after creation
- Participants can report scores
- Wagers are visible only to participants
- Settlement is creator-only or consensus-based via RPC

Recommendation:

Use RPCs for:

- creating a match from a round
- joining participants
- posting finalized scores
- calculating match results
- settling wagers
- recalculating handicap index

This keeps business logic in one place and prevents the client from composing invalid states.

## App Changes

## New Types

Add types in `src/types.ts` for:

- `HandicapProfile`
- `HandicapDifferential`
- `Scorecard`
- `ScorecardHole`
- `Match`
- `MatchParticipant`
- `MatchResult`
- `Wager`

## New Hooks

Add hooks:

- `useScorecards(roundId)`
- `useHandicap(userId?)`
- `useMatches(roundId?)`
- `useSeries(seriesId)`
- `useLeaderboard(scope)`

## Data Context Additions

Extend `DataContext` with mutations like:

- `createScorecard`
- `saveHoleScore`
- `finalizeScorecard`
- `createMatch`
- `joinMatch`
- `finalizeMatch`
- `createSeries`
- `settleWager`

## Screen Plan

### 1. Round Detail Enhancements

Extend [src/screens/RoundDetailScreen.tsx](/Users/lukemck/Development/tee-circle/src/screens/RoundDetailScreen.tsx).

Add sections:

- Scorecards
- Matchups
- Wagers
- Round leaderboard

This should become the operational hub for a round after tee time.

### 2. New Score Entry Screen

Add `RoundScoreScreen`.

Flow:

- choose player
- enter total score or hole-by-hole scores
- show gross and projected net
- finalize round score

### 3. New Match Creation Screen

Add `CreateMatchScreen`.

Inputs:

- players
- format
- wager amount
- handicap mode
- single-round vs series

### 4. New Leaderboard Screen

Add `LeaderboardScreen`.

Tabs:

- Friends
- This season
- Money
- Handicap

### 5. Profile Enhancements

Extend [src/screens/ProfileScreen.tsx](/Users/lukemck/Development/tee-circle/src/screens/ProfileScreen.tsx).

Add:

- current handicap
- handicap history sparkline
- rounds counted
- match record
- net scoring average

## Navigation Changes

Extend [src/navigation/types.ts](/Users/lukemck/Development/tee-circle/src/navigation/types.ts) with:

- `RoundScore`
- `CreateMatch`
- `MatchDetail`
- `Leaderboard`
- `SeriesDetail`

## Recommended UX Flow

### Post-Round Score Flow

1. User opens a past or active round
2. User taps `Enter Scores`
3. User enters gross score or hole scores
4. App calculates gross, net, and handicap differential
5. Round detail updates with match standings and wager results

### Match Flow

1. Organizer creates round
2. Friends accept
3. Organizer taps `Create Match`
4. Picks players, format, and wager
5. After scores are entered, match settles automatically

### Multi-Round Flow

1. User creates a `Series`
2. Adds round 1 immediately
3. Adds future rounds later
4. Series standings update after each round

## Calculation Rules

Keep all scoring rules on the backend.

### Handicap

Recommended v1:

- Calculate a TeeCircle handicap using stored differentials
- Use best recent differentials from eligible rounds
- Store a snapshot on every scorecard and match participant row

Do not attempt exact USGA parity in v1 unless you are ready to support full edge cases and course data requirements.

### Net Scoring

For each scorecard:

- `net_score = gross_score - playing_handicap`

For match play:

- Allocate strokes by hole using stroke index and player handicap delta

For Nassau:

- Treat front 9, back 9, and total as three separate wager ledgers

## Release Order With Repo Tasks

### Phase 1: Schema + Basic Score Entry

Deliverables:

- SQL migrations for `player_handicap_profiles`, `scorecards`, `scorecard_holes`, `handicap_differentials`
- RLS policies
- `useScorecards` and `useHandicap`
- `RoundScoreScreen`
- round detail summary card

Success criteria:

- A player can post a score to a round
- Handicap updates from posted scores

### Phase 2: Match Engine

Deliverables:

- SQL migrations for `matches`, `match_participants`, `match_results`, `wagers`, `wager_entries`
- RPCs for match creation and settlement
- `CreateMatchScreen`
- match summary in round detail

Success criteria:

- Friends can create and settle a handicap match on a round

### Phase 3: Series + Leaderboards

Deliverables:

- `match_series`
- series standings views
- `LeaderboardScreen`
- profile stats

Success criteria:

- Users can compare results over time and run multi-round competitions

## Risks and Decisions To Settle Early

### 1. Handicap source

Decision:

- in-app only for v1

Reason:

- avoids GHIN licensing and external dependencies

### 2. Money handling

Decision:

- track wagers only

Reason:

- avoids payment regulation and significantly reduces compliance risk

### 3. Score authority

Decision:

- player or round creator can submit scores
- optionally require player confirmation later

Reason:

- keeps the flow moving without overbuilding consensus workflows

### 4. Match formats

Decision:

- start with net stroke play, match play, Nassau

Reason:

- broad appeal and manageable rules engine

## Recommended First Build Slice

If building immediately, start here:

1. Add `scorecards`
2. Add `player_handicap_profiles`
3. Build `RoundScoreScreen`
4. Show current handicap in profile
5. Add `matches` for single-round net stroke play only

That is the smallest version that creates real user value and proves the game loop:

- schedule round
- play round
- enter score
- handicap updates
- compare net results with friends

## Suggested Next Implementation Task

Implement Phase 1 first.

Concrete repo task list:

1. Add SQL files for scorecards and handicap tables under `supabase/`
2. Add TypeScript domain types in `src/types.ts`
3. Add `useScorecards.ts` and `useHandicap.ts`
4. Add `RoundScoreScreen.tsx`
5. Extend round detail navigation and UI to launch score entry
6. Extend profile screen with handicap summary

