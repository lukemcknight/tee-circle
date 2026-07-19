-- The schema migration commits before the RLS policy migration. Supabase's
-- production default ACL grants anon/authenticated broad privileges on newly
-- created public relations, so migration 001 itself must fail closed.

begin;

do $$
declare
  v_table text;
  v_role text;
  v_privilege text;
  v_policy_count integer;
begin
  foreach v_table in array array[
    'trips',
    'trip_players',
    'course_cards',
    'course_card_holes',
    'round_holes',
    'trip_round_players',
    'trip_hole_scores',
    'trip_score_audit',
    'trip_leaderboard_snapshots',
    'trip_invites',
    'extension_sessions',
    'native_device_tokens',
    'live_activity_subscriptions',
    'trip_purchase_intents',
    'trip_entitlements'
  ] loop
    if not (
      select c.relrowsecurity
      from pg_catalog.pg_class c
      where c.oid = pg_catalog.to_regclass('public.' || v_table)
    ) then
      raise exception 'migration 001 left RLS disabled on public.%', v_table;
    end if;

    foreach v_role in array array['anon', 'authenticated'] loop
      foreach v_privilege in array array[
        'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
      ] loop
        if pg_catalog.has_table_privilege(
          v_role,
          pg_catalog.format('public.%I', v_table),
          v_privilege
        ) then
          raise exception 'migration 001 left % privilege on public.% for %',
            v_privilege, v_table, v_role;
        end if;
      end loop;
    end loop;
  end loop;

  if pg_catalog.has_sequence_privilege(
    'anon', 'public.trip_score_audit_id_seq', 'USAGE'
  ) or pg_catalog.has_sequence_privilege(
    'authenticated', 'public.trip_score_audit_id_seq', 'USAGE'
  ) then
    raise exception 'migration 001 exposed the trip score audit identity sequence';
  end if;

  if pg_catalog.has_schema_privilege('anon', 'tee_internal', 'USAGE')
     or pg_catalog.has_schema_privilege('authenticated', 'tee_internal', 'USAGE') then
    raise exception 'migration 001 exposed tee_internal schema usage';
  end if;

  select count(*) into v_policy_count
  from pg_catalog.pg_policy p
  where p.polrelid = 'public.rounds'::regclass
    and not p.polpermissive
    and p.polroles @> array[
      (select oid from pg_catalog.pg_roles where rolname = 'authenticated')
    ]::oid[]
    and p.polname in (
      'Native trip rounds block direct inserts',
      'Native trip rounds block direct updates',
      'Native trip rounds block direct deletes'
    );

  if v_policy_count <> 3 then
    raise exception 'migration 001 did not install all restrictive legacy/native round boundaries';
  end if;
end
$$;

rollback;
