-- Reset round_responses RLS policies to remove recursion.
do $$
declare pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'round_responses'
  loop
    execute format('drop policy if exists %I on public.round_responses', pol.policyname);
  end loop;
end
$$;

alter table public.round_responses enable row level security;

create policy "Invitee or round creator can view response"
on public.round_responses
for select
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.rounds r
    where r.id = round_responses.round_id
      and r.created_by = auth.uid()
  )
);

create policy "Round creator can insert their own response"
on public.round_responses
for insert
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.rounds r
    where r.id = round_responses.round_id
      and r.created_by = auth.uid()
  )
);

create policy "Invitee can update their own response"
on public.round_responses
for update
using (user_id = auth.uid());

create policy "Round creator can delete responses"
on public.round_responses
for delete
using (
  exists (
    select 1
    from public.rounds r
    where r.id = round_responses.round_id
      and r.created_by = auth.uid()
  )
);
