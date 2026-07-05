-- Trigger to automatically create the round creator's response when a round is created.
-- This ensures the creator always has a response row they can update.

-- Ensure unique constraint exists for the ON CONFLICT clause
-- (This is idempotent - won't fail if constraint already exists)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'round_responses_round_id_user_id_key'
  ) then
    alter table public.round_responses
      add constraint round_responses_round_id_user_id_key
      unique (round_id, user_id);
  end if;
end
$$;

-- Create the trigger function
create or replace function public.create_creator_response()
returns trigger as $$
begin
  -- Insert a 'yes' response for the round creator
  insert into public.round_responses (round_id, user_id, response, responded_at)
  values (NEW.id, NEW.created_by, 'yes', now())
  on conflict (round_id, user_id) do nothing;

  return NEW;
end;
$$ language plpgsql security definer;

-- Drop the trigger if it exists (for idempotency)
drop trigger if exists on_round_created_add_creator_response on public.rounds;

-- Create the trigger
create trigger on_round_created_add_creator_response
  after insert on public.rounds
  for each row
  execute function public.create_creator_response();
