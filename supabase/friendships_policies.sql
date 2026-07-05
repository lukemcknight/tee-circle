-- RLS policies for friendships table.
-- Users can only see friendships they are part of.

alter table public.friendships enable row level security;

-- Drop existing policies for idempotency
do $$
declare pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'friendships'
  loop
    execute format('drop policy if exists %I on public.friendships', pol.policyname);
  end loop;
end
$$;

-- Users can view friendships they are part of (either as user_low or user_high)
create policy "Users can view own friendships"
on public.friendships
for select
using (
  auth.uid() = user_low
  or auth.uid() = user_high
);

-- Users can update friendships they are part of (for accepting requests)
create policy "Users can update own friendships"
on public.friendships
for update
using (
  auth.uid() = user_low
  or auth.uid() = user_high
);

-- Note: INSERT and DELETE are handled via RPCs, not direct table access
