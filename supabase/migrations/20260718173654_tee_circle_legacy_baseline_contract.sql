set lock_timeout = '10s';
set statement_timeout = '5min';

-- TeeCircle production legacy-baseline contract marker.
--
-- This migration intentionally creates, alters, and deletes nothing. It is
-- ordered before every native-v2 migration so the linked project fails closed
-- unless the reviewed Expo schema is still the schema we audited. A successful
-- run only records this marker in Supabase migration history.


do $$
declare
  v_actual_columns text[];
  v_default text;
  v_enum_labels text[];
  v_expected record;
  v_function regprocedure;
  v_missing text[] := array[]::text[];
  v_relation text;
  v_type oid;
  v_not_null boolean;
begin
  -- Required linked-project relations -------------------------------------
  foreach v_relation in array array[
    'auth.users',
    'public.profiles',
    'public.groups',
    'public.group_members',
    'public.friendships',
    'public.rounds',
    'public.round_responses',
    'public.player_handicap_profiles',
    'public.scorecards',
    'public.scorecard_holes',
    'public.handicap_differentials'
  ] loop
    if not exists (
      select 1
      from pg_catalog.pg_class c
      where c.oid = to_regclass(v_relation)
        and c.relkind in ('r', 'p')
    ) then
      v_missing := array_append(v_missing, v_relation || ' table');
    end if;
  end loop;

  -- Exact legacy enum labels and ordering ---------------------------------
  for v_expected in
    select *
    from (values
      ('public.friendship_status', array['pending', 'accepted']::text[]),
      ('public.response_status', array['yes', 'no', 'pending']::text[]),
      ('public.round_status', array['open', 'locked']::text[])
    ) as expected(type_name, labels)
  loop
    select array_agg(e.enumlabel::text order by e.enumsortorder)
      into v_enum_labels
    from pg_catalog.pg_type t
    join pg_catalog.pg_namespace n on n.oid = t.typnamespace
    join pg_catalog.pg_enum e on e.enumtypid = t.oid
    where t.oid = to_regtype(v_expected.type_name)
      and t.typtype = 'e';

    if v_enum_labels is distinct from v_expected.labels then
      v_missing := array_append(
        v_missing,
        format('%s enum labels expected %s, found %s',
          v_expected.type_name,
          v_expected.labels,
          coalesce(v_enum_labels::text, '<missing>'))
      );
    end if;
  end loop;

  -- Exact pre-v2 rounds and round_responses column sets -------------------
  if to_regclass('public.rounds') is not null then
    select array_agg(a.attname::text order by a.attnum)
      into v_actual_columns
    from pg_catalog.pg_attribute a
    where a.attrelid = 'public.rounds'::regclass
      and a.attnum > 0
      and not a.attisdropped;

    if v_actual_columns is distinct from array[
      'id',
      'group_id',
      'course_name',
      'tee_time',
      'holes',
      'walk_ride',
      'status',
      'created_by',
      'created_at',
      'course_place_id',
      'course_address',
      'course_lat',
      'course_lng'
    ]::text[] then
      v_missing := array_append(
        v_missing,
        format('public.rounds columns expected audited legacy order, found %s',
          coalesce(v_actual_columns::text, '<missing>'))
      );
    end if;
  end if;

  if to_regclass('public.round_responses') is not null then
    select array_agg(a.attname::text order by a.attnum)
      into v_actual_columns
    from pg_catalog.pg_attribute a
    where a.attrelid = 'public.round_responses'::regclass
      and a.attnum > 0
      and not a.attisdropped;

    if v_actual_columns is distinct from array[
      'round_id',
      'user_id',
      'response',
      'responded_at'
    ]::text[] then
      v_missing := array_append(
        v_missing,
        format('public.round_responses columns expected audited legacy order, found %s',
          coalesce(v_actual_columns::text, '<missing>'))
      );
    end if;
  end if;

  -- Column type, nullability, and default contracts used by native v2.
  for v_expected in
    select *
    from (values
      ('public.rounds', 'id', 'uuid', true, 'uuid'),
      ('public.rounds', 'group_id', 'uuid', false, 'none'),
      ('public.rounds', 'course_name', 'text', true, 'none'),
      ('public.rounds', 'tee_time', 'timestamp with time zone', true, 'none'),
      ('public.rounds', 'holes', 'integer', false, 'none'),
      ('public.rounds', 'walk_ride', 'text', false, 'none'),
      ('public.rounds', 'status', 'public.round_status', false, 'open'),
      ('public.rounds', 'created_by', 'uuid', false, 'none'),
      ('public.rounds', 'created_at', 'timestamp with time zone', false, 'now'),
      ('public.rounds', 'course_place_id', 'text', false, 'none'),
      ('public.rounds', 'course_address', 'text', false, 'none'),
      ('public.rounds', 'course_lat', 'double precision', false, 'none'),
      ('public.rounds', 'course_lng', 'double precision', false, 'none'),
      ('public.round_responses', 'round_id', 'uuid', true, 'none'),
      ('public.round_responses', 'user_id', 'uuid', true, 'none'),
      ('public.round_responses', 'response', 'public.response_status', false, 'pending'),
      ('public.round_responses', 'responded_at', 'timestamp with time zone', false, 'none')
    ) as expected(table_name, column_name, type_name, not_null, default_kind)
  loop
    select a.atttypid, a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
      into v_type, v_not_null, v_default
    from pg_catalog.pg_attribute a
    left join pg_catalog.pg_attrdef d
      on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = to_regclass(v_expected.table_name)
      and a.attname = v_expected.column_name
      and a.attnum > 0
      and not a.attisdropped;

    if not found then
      v_missing := array_append(
        v_missing,
        format('%s.%s column', v_expected.table_name, v_expected.column_name)
      );
      continue;
    end if;

    if v_type is distinct from to_regtype(v_expected.type_name)
       or v_not_null is distinct from v_expected.not_null then
      v_missing := array_append(
        v_missing,
        format('%s.%s expected %s not_null=%s',
          v_expected.table_name,
          v_expected.column_name,
          v_expected.type_name,
          v_expected.not_null)
      );
    end if;

    if (v_expected.default_kind = 'none' and v_default is not null)
       or (v_expected.default_kind = 'uuid'
           and coalesce(v_default, '') not like '%gen_random_uuid%')
       or (v_expected.default_kind = 'now'
           and coalesce(v_default, '') not like '%now()%')
       or (v_expected.default_kind = 'open'
           and coalesce(v_default, '') not like '%''open''%')
       or (v_expected.default_kind = 'pending'
           and coalesce(v_default, '') not like '%''pending''%') then
      v_missing := array_append(
        v_missing,
        format('%s.%s default expected %s, found %s',
          v_expected.table_name,
          v_expected.column_name,
          v_expected.default_kind,
          coalesce(v_default, '<none>'))
      );
    end if;
  end loop;

  -- Profile-backed and parent foreign-key behavior ------------------------
  for v_expected in
    select *
    from (values
      ('public.profiles', 'id', 'auth.users', 'id', 'c'),
      ('public.groups', 'created_by', 'public.profiles', 'id', 'a'),
      ('public.group_members', 'user_id', 'public.profiles', 'id', 'c'),
      ('public.friendships', 'user_low', 'public.profiles', 'id', 'c'),
      ('public.friendships', 'user_high', 'public.profiles', 'id', 'c'),
      ('public.friendships', 'requested_by', 'public.profiles', 'id', 'c'),
      ('public.rounds', 'group_id', 'public.groups', 'id', 'c'),
      ('public.rounds', 'created_by', 'public.profiles', 'id', 'a'),
      ('public.round_responses', 'round_id', 'public.rounds', 'id', 'c'),
      ('public.round_responses', 'user_id', 'public.profiles', 'id', 'c'),
      ('public.player_handicap_profiles', 'user_id', 'auth.users', 'id', 'c'),
      ('public.scorecards', 'round_id', 'public.rounds', 'id', 'c'),
      ('public.scorecards', 'player_id', 'auth.users', 'id', 'c'),
      ('public.scorecards', 'entered_by', 'auth.users', 'id', 'c'),
      ('public.scorecard_holes', 'scorecard_id', 'public.scorecards', 'id', 'c'),
      ('public.handicap_differentials', 'user_id', 'auth.users', 'id', 'c'),
      ('public.handicap_differentials', 'round_id', 'public.rounds', 'id', 'n'),
      ('public.handicap_differentials', 'scorecard_id', 'public.scorecards', 'id', 'c')
    ) as expected(source_table, source_column, target_table, target_column, delete_action)
  loop
    if not exists (
      select 1
      from pg_catalog.pg_constraint con
      join pg_catalog.pg_attribute source_attribute
        on source_attribute.attrelid = con.conrelid
       and source_attribute.attnum = con.conkey[1]
      join pg_catalog.pg_attribute target_attribute
        on target_attribute.attrelid = con.confrelid
       and target_attribute.attnum = con.confkey[1]
      where con.contype = 'f'
        and con.conrelid = to_regclass(v_expected.source_table)
        and con.confrelid = to_regclass(v_expected.target_table)
        and array_length(con.conkey, 1) = 1
        and array_length(con.confkey, 1) = 1
        and source_attribute.attname = v_expected.source_column
        and target_attribute.attname = v_expected.target_column
        and con.confdeltype = v_expected.delete_action::"char"
    ) then
      v_missing := array_append(
        v_missing,
        format('%s.%s -> %s.%s foreign key (delete action %s)',
          v_expected.source_table,
          v_expected.source_column,
          v_expected.target_table,
          v_expected.target_column,
          v_expected.delete_action)
      );
    end if;
  end loop;

  -- Every audited public table must retain RLS and at least one policy.
  foreach v_relation in array array[
    'public.profiles',
    'public.groups',
    'public.group_members',
    'public.friendships',
    'public.rounds',
    'public.round_responses',
    'public.player_handicap_profiles',
    'public.scorecards',
    'public.scorecard_holes',
    'public.handicap_differentials'
  ] loop
    if not coalesce((
      select c.relrowsecurity
      from pg_catalog.pg_class c
      where c.oid = to_regclass(v_relation)
    ), false) then
      v_missing := array_append(v_missing, v_relation || ' RLS enabled');
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_policy p
      where p.polrelid = to_regclass(v_relation)
    ) then
      v_missing := array_append(v_missing, v_relation || ' RLS policies');
    end if;
  end loop;

  -- Legacy functions, trigger wiring, and visible-rounds view -------------
  for v_expected in
    select *
    from (values
      ('public.create_creator_response()', true, 'trigger'),
      ('public.lock_round_if_ready()', false, 'trigger'),
      ('public.invite_friend_to_round(uuid,uuid)', true, 'boolean'),
      ('public.delete_user_account()', true, 'void')
    ) as expected(signature, security_definer, return_type)
  loop
    v_function := to_regprocedure(v_expected.signature);
    if v_function is null
       or not exists (
         select 1
         from pg_catalog.pg_proc p
         where p.oid = v_function::oid
           and p.prosecdef = v_expected.security_definer
           and p.prorettype = to_regtype(v_expected.return_type)
       ) then
      v_missing := array_append(
        v_missing,
        format('%s function security/return contract', v_expected.signature)
      );
    end if;
  end loop;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = to_regclass('public.rounds')
      and t.tgname = 'on_round_created_add_creator_response'
      and t.tgfoid = to_regprocedure('public.create_creator_response()')::oid
      and not t.tgisinternal
      and t.tgenabled <> 'D'
      and lower(pg_get_triggerdef(t.oid, true)) like '%after insert on rounds%'
  ) then
    v_missing := array_append(v_missing, 'round creator-response trigger');
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = to_regclass('public.round_responses')
      and t.tgname = 'check_round_lock'
      and t.tgfoid = to_regprocedure('public.lock_round_if_ready()')::oid
      and not t.tgisinternal
      and t.tgenabled <> 'D'
      and lower(pg_get_triggerdef(t.oid, true)) like '%after update on round_responses%'
  ) then
    v_missing := array_append(v_missing, 'round response-lock trigger');
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class c
    where c.oid = to_regclass('public.visible_rounds')
      and c.relkind = 'v'
  ) then
    v_missing := array_append(v_missing, 'public.visible_rounds view');
  else
    select array_agg(a.attname::text order by a.attnum)
      into v_actual_columns
    from pg_catalog.pg_attribute a
    where a.attrelid = 'public.visible_rounds'::regclass
      and a.attnum > 0
      and not a.attisdropped;

    if v_actual_columns is distinct from array[
      'id',
      'group_id',
      'course_name',
      'course_place_id',
      'course_address',
      'course_lat',
      'course_lng',
      'tee_time',
      'holes',
      'walk_ride',
      'status',
      'created_by',
      'created_at'
    ]::text[] then
      v_missing := array_append(v_missing, 'public.visible_rounds audited columns');
    end if;
  end if;

  -- The linked project has Supabase's internal messages publication plus an
  -- empty supabase_realtime publication. Native v2 adds only the canonical
  -- snapshot table to that existing publication in 010.
  if not exists (
    select 1
    from pg_catalog.pg_publication p
    where p.pubname = 'supabase_realtime'
      and not p.puballtables
  ) or exists (
    select 1
    from pg_catalog.pg_publication p
    join pg_catalog.pg_publication_rel pr on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime'
  ) then
    v_missing := array_append(
      v_missing,
      'supabase_realtime must exist with puballtables=false and no table membership'
    );
  end if;

  if exists (
    select 1
    from pg_catalog.pg_publication p
    left join pg_catalog.pg_publication_rel pr on pr.prpubid = p.oid
    where p.puballtables
       or pr.prrelid in (
      'public.profiles'::regclass,
      'public.groups'::regclass,
      'public.group_members'::regclass,
      'public.friendships'::regclass,
      'public.rounds'::regclass,
      'public.round_responses'::regclass,
      'public.player_handicap_profiles'::regclass,
      'public.scorecards'::regclass,
      'public.scorecard_holes'::regclass,
      'public.handicap_differentials'::regclass
    )
  ) then
    v_missing := array_append(v_missing, 'legacy public tables must not belong to a publication');
  end if;

  -- This marker may never run after a partial or complete native-v2 install.
  if to_regnamespace('tee_internal') is not null then
    v_missing := array_append(v_missing, 'tee_internal must not preexist');
  end if;

  if to_regprocedure('public.delete_round(uuid)') is not null then
    v_missing := array_append(v_missing, 'public.delete_round(uuid) must not preexist');
  end if;

  foreach v_relation in array array[
    'public.trips',
    'public.trip_players',
    'public.course_cards',
    'public.course_card_holes',
    'public.round_holes',
    'public.trip_round_players',
    'public.trip_hole_scores',
    'public.trip_score_audit',
    'public.trip_leaderboard_snapshots',
    'public.trip_invites',
    'public.extension_sessions',
    'public.native_device_tokens',
    'public.live_activity_subscriptions',
    'public.trip_purchase_intents',
    'public.trip_entitlements'
  ] loop
    if to_regclass(v_relation) is not null then
      v_missing := array_append(v_missing, v_relation || ' must not preexist');
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception using
      errcode = 'P0001',
      message = 'legacy_baseline_contract_mismatch',
      detail = array_to_string(v_missing, E'\n'),
      hint = 'Stop before native-v2 migrations. Re-audit the linked Supabase schema; never replay the test fixture or a baseline dump over production.';
  end if;
end
$$;
