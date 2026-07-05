-- Allow users to view their own profile and friends'/pending request profiles.
alter table public.profiles enable row level security;
-- Drop existing policy first for idempotency
do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can delete own profile'
  ) then
    drop policy "Users can delete own profile" on public.profiles;
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can view profiles of accepted friends'
  ) then
    drop policy "Users can view profiles of accepted friends" on public.profiles;
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can view relevant profiles'
  ) then
    drop policy "Users can view relevant profiles" on public.profiles;
  end if;
end
$$;

create policy "Users can view relevant profiles"
on public.profiles
for select
using (
  auth.uid() = id
  or exists (
    select 1
    from public.friendships f
    where (
        (f.user_low = auth.uid() and f.user_high = profiles.id)
        or
        (f.user_high = auth.uid() and f.user_low = profiles.id)
      )
    -- Allow viewing profiles for both pending and accepted friendships
  )
);

create policy "Users can delete own profile"
on public.profiles
for delete
using (auth.uid() = id);
