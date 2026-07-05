-- RPC function for safe profile deletion.
-- Cleans up all related data before deleting the profile.

create or replace function delete_user_account()
returns void as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Delete friendships where user is involved
  delete from public.friendships
  where user_low = uid or user_high = uid;

  -- Delete group memberships
  delete from public.group_members
  where user_id = uid;

  -- Delete round responses
  delete from public.round_responses
  where user_id = uid;

  -- Delete push tokens if table exists
  if to_regclass('public.push_tokens') is not null then
    delete from public.push_tokens
    where user_id = uid;
  end if;

  -- Delete rounds created by user (or reassign ownership if preferred)
  delete from public.rounds
  where created_by = uid;

  -- Delete groups created by user (or reassign ownership if preferred)
  delete from public.groups
  where created_by = uid;

  -- Finally delete the profile
  delete from public.profiles
  where id = uid;
end;
$$ language plpgsql security definer;

-- Grant execute permission to authenticated users
grant execute on function delete_user_account() to authenticated;
