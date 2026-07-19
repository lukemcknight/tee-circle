set lock_timeout = '10s';
set statement_timeout = '5min';

-- Keep client unlock state aligned with the server purchase gate. A bounded
-- pilot can disable purchases_required without making clients show a paywall
-- that the lifecycle and score commands no longer enforce.


-- Preserve the sanitized bootstrap contract: expose only the effective
-- boolean, never entitlement rows, transaction identifiers, or environment.
create or replace function public.get_trip_bootstrap_v1(p_trip_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_response jsonb;
begin
  v_response := tee_internal.get_trip_bootstrap_unfiltered_v1(p_trip_id);
  if v_response ? 'error' then
    return v_response;
  end if;
  return jsonb_set(
    v_response,
    '{data,trip,isUnlocked}',
    to_jsonb(not tee_internal.trip_unlock_required_v1(p_trip_id)),
    true
  );
end;
$$;

-- Messages uses the domain name isEntitled, but it represents the same
-- effective capability. Extension clients therefore follow the pilot gate
-- without receiving raw purchase provenance.
create or replace function public.get_messages_bootstrap_service_v1(
  p_token_hash_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_response jsonb;
  v_trip_id uuid;
begin
  v_response := tee_internal.get_messages_bootstrap_unfiltered_service_v1(
    p_token_hash_hex
  );
  if v_response ? 'error' then
    return v_response;
  end if;
  v_trip_id := (v_response#>>'{data,trip,id}')::uuid;
  return jsonb_set(
    v_response,
    '{data,trip,isEntitled}',
    to_jsonb(not tee_internal.trip_unlock_required_v1(v_trip_id)),
    true
  );
exception
  when invalid_text_representation then
    return tee_internal.api_error(
      gen_random_uuid(),
      'invalid_bootstrap',
      'The Messages trip response is invalid.',
      true
    );
end;
$$;

revoke all on function public.get_trip_bootstrap_v1(uuid)
  from public, anon;
revoke all on function public.get_messages_bootstrap_service_v1(text)
  from public, anon, authenticated;
grant execute on function public.get_trip_bootstrap_v1(uuid)
  to authenticated;
grant execute on function public.get_messages_bootstrap_service_v1(text)
  to service_role;
