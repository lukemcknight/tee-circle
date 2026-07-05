-- Atomically delete a round and its responses.
-- Only the round creator can delete their own round.

create or replace function delete_round(p_round_id uuid)
returns boolean
language plpgsql
security definer
as $$
declare
  v_created_by uuid;
begin
  select created_by into v_created_by
  from rounds
  where id = p_round_id;

  if v_created_by is null or v_created_by <> auth.uid() then
    return false;
  end if;

  delete from round_responses where round_id = p_round_id;
  delete from rounds where id = p_round_id and created_by = auth.uid();

  return true;
end;
$$;

grant execute on function delete_round(uuid) to authenticated;
