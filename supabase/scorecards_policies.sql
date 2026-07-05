alter table public.player_handicap_profiles enable row level security;
alter table public.scorecards enable row level security;
alter table public.scorecard_holes enable row level security;
alter table public.handicap_differentials enable row level security;

do $$
declare pol record;
begin
  for pol in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('player_handicap_profiles', 'scorecards', 'scorecard_holes', 'handicap_differentials')
  loop
    execute format('drop policy if exists %I on public.%I', pol.policyname, pol.tablename);
  end loop;
end
$$;

create policy "Users can view own handicap profile or accepted friends"
on public.player_handicap_profiles
for select
using (
  auth.uid() = user_id
  or (
    not is_hidden
    and exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and (
          (f.user_low = auth.uid() and f.user_high = player_handicap_profiles.user_id)
          or (f.user_high = auth.uid() and f.user_low = player_handicap_profiles.user_id)
        )
    )
  )
);

create policy "Users can manage own handicap profile"
on public.player_handicap_profiles
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Round participants can view scorecards"
on public.scorecards
for select
using (
  auth.uid() = player_id
  or exists (
    select 1
    from public.rounds r
    where r.id = scorecards.round_id
      and r.created_by = auth.uid()
  )
  or exists (
    select 1
    from public.round_responses rr
    where rr.round_id = scorecards.round_id
      and rr.user_id = auth.uid()
      and rr.response = 'yes'
  )
);

create policy "Players and round creators can manage scorecards"
on public.scorecards
for all
using (
  auth.uid() = player_id
  or exists (
    select 1
    from public.rounds r
    where r.id = scorecards.round_id
      and r.created_by = auth.uid()
  )
)
with check (
  auth.uid() = player_id
  or exists (
    select 1
    from public.rounds r
    where r.id = scorecards.round_id
      and r.created_by = auth.uid()
  )
);

create policy "Round participants can view scorecard holes"
on public.scorecard_holes
for select
using (
  exists (
    select 1
    from public.scorecards s
    where s.id = scorecard_holes.scorecard_id
      and (
        s.player_id = auth.uid()
        or exists (
          select 1
          from public.rounds r
          where r.id = s.round_id
            and r.created_by = auth.uid()
        )
        or exists (
          select 1
          from public.round_responses rr
          where rr.round_id = s.round_id
            and rr.user_id = auth.uid()
            and rr.response = 'yes'
        )
      )
  )
);

create policy "Players and round creators can manage scorecard holes"
on public.scorecard_holes
for all
using (
  exists (
    select 1
    from public.scorecards s
    where s.id = scorecard_holes.scorecard_id
      and (
        s.player_id = auth.uid()
        or exists (
          select 1
          from public.rounds r
          where r.id = s.round_id
            and r.created_by = auth.uid()
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.scorecards s
    where s.id = scorecard_holes.scorecard_id
      and (
        s.player_id = auth.uid()
        or exists (
          select 1
          from public.rounds r
          where r.id = s.round_id
            and r.created_by = auth.uid()
        )
      )
  )
);

create policy "Users can view own handicap differentials or accepted friends"
on public.handicap_differentials
for select
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.friendships f
    where f.status = 'accepted'
      and (
        (f.user_low = auth.uid() and f.user_high = handicap_differentials.user_id)
        or (f.user_high = auth.uid() and f.user_low = handicap_differentials.user_id)
      )
  )
);

create policy "Users can manage own handicap differentials"
on public.handicap_differentials
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
