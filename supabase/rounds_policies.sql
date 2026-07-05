-- Allow the creator to delete their own round.
alter table public.rounds enable row level security;

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'rounds'
      and policyname = 'Round creator can view round'
  ) then
    drop policy "Round creator can view round" on public.rounds;
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'rounds'
      and policyname = 'Round creator can insert round'
  ) then
    drop policy "Round creator can insert round" on public.rounds;
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'rounds'
      and policyname = 'Round creator can delete round'
  ) then
    drop policy "Round creator can delete round" on public.rounds;
  end if;
end
$$;

create policy "Round creator can view round"
on public.rounds
for select
using (created_by = auth.uid());

create policy "Round creator can insert round"
on public.rounds
for insert
with check (created_by = auth.uid());

create policy "Round creator can delete round"
on public.rounds
for delete
using (created_by = auth.uid());
