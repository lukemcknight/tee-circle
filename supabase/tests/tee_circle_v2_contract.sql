-- Run after the legacy baseline and all TeeCircle 2.0 migrations:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/tee_circle_v2_contract.sql

begin;

do $$
declare
  v_table text;
  v_flag_count integer;
  v_proc regprocedure;
  v_source text;
  v_columns text[];
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
    if to_regclass('public.' || v_table) is null then
      raise exception 'missing v2 table: %', v_table;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || v_table)) then
      raise exception 'RLS is disabled on public.%', v_table;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.trip_hole_scores', 'INSERT')
     or has_table_privilege('authenticated', 'public.trip_hole_scores', 'UPDATE')
     or has_table_privilege('authenticated', 'public.trip_hole_scores', 'DELETE') then
    raise exception 'authenticated can mutate trip_hole_scores directly';
  end if;
  if has_table_privilege('anon', 'public.trip_invites', 'SELECT')
     or has_table_privilege('authenticated', 'public.extension_sessions', 'SELECT')
     or has_table_privilege('authenticated', 'public.native_device_tokens', 'SELECT')
     or has_table_privilege('authenticated', 'public.trip_purchase_intents', 'SELECT')
     or has_table_privilege('authenticated', 'public.trip_entitlements', 'SELECT') then
    raise exception 'bearer hashes, push tokens, or payment evidence are directly readable';
  end if;

  if has_table_privilege('authenticated', 'public.trip_players', 'SELECT')
     or has_column_privilege(
       'authenticated', 'public.trip_players', 'claimed_user_id', 'SELECT'
     )
     or not has_column_privilege(
       'authenticated', 'public.trip_players', 'display_name', 'SELECT'
     )
     or not has_column_privilege(
       'authenticated', 'public.trip_players', 'handicap_snapshot', 'SELECT'
     ) then
    raise exception 'roster column privacy boundary is unsafe';
  end if;

  foreach v_proc in array array[
    to_regprocedure('tee_internal.is_trip_member(uuid,uuid)'),
    to_regprocedure('tee_internal.trip_role(uuid,uuid)'),
    to_regprocedure('tee_internal.can_manage_trip(uuid,uuid)'),
    to_regprocedure('tee_internal.can_score_player(uuid,uuid,uuid)')
  ] loop
    if v_proc is null
       or has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or not has_function_privilege('service_role', v_proc, 'EXECUTE') then
      raise exception 'explicit-user authorization helper is client-executable: %', v_proc;
    end if;
  end loop;

  foreach v_proc in array array[
    to_regprocedure('tee_internal.current_user_is_trip_member(uuid)'),
    to_regprocedure('tee_internal.current_user_trip_role(uuid)'),
    to_regprocedure('tee_internal.current_user_can_manage_trip(uuid)'),
    to_regprocedure('tee_internal.current_user_can_score_player(uuid,uuid)')
  ] loop
    if v_proc is null
       or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or has_function_privilege('anon', v_proc, 'EXECUTE') then
      raise exception 'auth-bound authorization wrapper is unsafe: %', v_proc;
    end if;
  end loop;

  v_proc := to_regprocedure('public.record_hole_score_v1(uuid,uuid,smallint,smallint,smallint,uuid,bigint)');
  if v_proc is null
     or has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or has_function_privilege('service_role', v_proc, 'EXECUTE') then
    raise exception 'raw score command bypasses the synchronous Edge pipeline';
  end if;
  v_proc := to_regprocedure('public.record_authenticated_hole_score_service_v1(uuid,uuid,uuid,smallint,smallint,smallint,uuid,bigint)');
  if v_proc is null
     or has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or not has_function_privilege('service_role', v_proc, 'EXECUTE') then
    raise exception 'authenticated score service bridge privileges are unsafe';
  end if;
  v_proc := to_regprocedure('public.claim_trip_player_v1(uuid)');
  if v_proc is null
     or has_function_privilege('anon', v_proc, 'EXECUTE')
     or has_function_privilege('authenticated', v_proc, 'EXECUTE') then
    raise exception 'direct roster claim bypass is executable';
  end if;
  v_proc := to_regprocedure('public.accept_trip_invite_v1(text,uuid)');
  if v_proc is null or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or has_function_privilege('anon', v_proc, 'EXECUTE') then
    raise exception 'authenticated invite acceptance privileges are unsafe';
  end if;
  v_proc := to_regprocedure('public.get_course_cards_v1()');
  if v_proc is null or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or has_function_privilege('anon', v_proc, 'EXECUTE') then
    raise exception 'authenticated course-card read privileges are unsafe';
  end if;
  foreach v_proc in array array[
    to_regprocedure('public.update_course_card_v1(uuid,jsonb,timestamptz)'),
    to_regprocedure('public.update_trip_round_v1(uuid,jsonb,timestamptz)'),
    to_regprocedure('public.delete_trip_round_v1(uuid,uuid,timestamptz)'),
    to_regprocedure('public.delete_trip_player_v1(uuid,uuid,timestamptz)')
  ] loop
    if v_proc is null or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or has_function_privilege('anon', v_proc, 'EXECUTE') then
      raise exception 'native edit/delete command privileges are unsafe: %', v_proc;
    end if;
  end loop;
  if to_regprocedure('public.delete_account_v1(uuid)') is not null
     or to_regclass('tee_internal.account_deletion_requests') is not null then
    raise exception 'unsafe account hard-deletion implementation is present';
  end if;
  v_proc := to_regprocedure('public.persist_trip_snapshot_v1(uuid,bigint,jsonb,text)');
  if v_proc is null
     or has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or not has_function_privilege('service_role', v_proc, 'EXECUTE') then
    raise exception 'snapshot persistence privileges are unsafe';
  end if;
  v_proc := to_regprocedure('public.record_extension_hole_score_service_v1(text,uuid,uuid,smallint,smallint,smallint,uuid,bigint)');
  if v_proc is null
     or has_function_privilege('anon', v_proc, 'EXECUTE')
     or has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or not has_function_privilege('service_role', v_proc, 'EXECUTE') then
    raise exception 'Messages score service privileges are unsafe';
  end if;
  foreach v_proc in array array[
    to_regprocedure('public.start_trip_v1(uuid,bigint)'),
    to_regprocedure('public.advance_trip_round_v1(uuid,uuid,bigint,boolean)')
  ] loop
    if v_proc is null
       or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or has_function_privilege('anon', v_proc, 'EXECUTE') then
      raise exception 'atomic lifecycle command privileges are unsafe: %', v_proc;
    end if;
  end loop;
  v_proc := to_regprocedure('public.set_trip_round_status_v1(uuid,text,text,boolean)');
  if v_proc is null or has_function_privilege('authenticated', v_proc, 'EXECUTE') then
    raise exception 'non-atomic round lifecycle command remains executable';
  end if;
  foreach v_proc in array array[
    to_regprocedure('public.get_latest_activity_snapshots_service_v1(uuid[],bigint)'),
    to_regprocedure('public.lease_live_activity_deliveries_service_v1(uuid,bigint,integer)'),
    to_regprocedure('public.complete_live_activity_delivery_service_v1(uuid,bigint,uuid,text,boolean)'),
    to_regprocedure('public.get_runtime_flag_service_v1(text)'),
    to_regprocedure('public.enqueue_missing_trip_snapshot_jobs_service_v1()')
  ] loop
    if v_proc is null
       or has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or not has_function_privilege('service_role', v_proc, 'EXECUTE') then
      raise exception 'release service command privileges are unsafe: %', v_proc;
    end if;
  end loop;
  v_proc := to_regprocedure('public.verify_trip_purchase_v1(uuid,text,text,text,timestamptz,timestamptz)');
  if v_proc is null
     or has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or not has_function_privilege('service_role', v_proc, 'EXECUTE')
     or to_regprocedure('public.verify_trip_purchase_v1(uuid,text,text,timestamptz)') is not null then
    raise exception 'purchase verification provenance boundary is unsafe';
  end if;
  v_proc := to_regprocedure('public.cancel_trip_purchase_intent_v1(uuid)');
  if v_proc is null
     or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or has_function_privilege('anon', v_proc, 'EXECUTE') then
    raise exception 'purchase cancellation privileges are unsafe';
  end if;
  foreach v_proc in array array[
    to_regprocedure('public.list_trip_invites_v1(uuid)'),
    to_regprocedure('public.rotate_trip_invite_v1(uuid,timestamptz,integer,uuid)'),
    to_regprocedure('public.revoke_trip_invite_v1(uuid)')
  ] loop
    if v_proc is null
       or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or has_function_privilege('anon', v_proc, 'EXECUTE') then
      raise exception 'invite lifecycle command privileges are unsafe: %', v_proc;
    end if;
  end loop;
  if to_regprocedure('public.get_trip_bootstrap_unfiltered_v1(uuid)') is not null
     or to_regprocedure('public.get_messages_bootstrap_unfiltered_service_v1(text)') is not null
     or has_function_privilege(
       'authenticated',
       'tee_internal.get_trip_bootstrap_unfiltered_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'tee_internal.get_messages_bootstrap_unfiltered_service_v1(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'tee_internal.start_trip_unfiltered_v1(uuid,bigint)',
       'EXECUTE'
     ) then
    raise exception 'unfiltered entitlement bootstrap remains executable';
  end if;

  v_proc := to_regprocedure('public.get_trip_bootstrap_v1(uuid)');
  if v_proc is null
     or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or has_function_privilege('anon', v_proc, 'EXECUTE')
     or position(
       'trip_unlock_required_v1'
       in pg_get_functiondef(v_proc::oid)
     ) = 0 then
    raise exception 'authenticated bootstrap does not expose sanitized effective unlock state';
  end if;
  v_proc := to_regprocedure('public.get_messages_bootstrap_service_v1(text)');
  if v_proc is null
     or has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or not has_function_privilege('service_role', v_proc, 'EXECUTE')
     or position(
       'trip_unlock_required_v1'
       in pg_get_functiondef(v_proc::oid)
     ) = 0 then
    raise exception 'Messages bootstrap does not expose sanitized effective unlock state';
  end if;

  -- Native trip rounds must remain detached from every profile-backed legacy
  -- creator/response trigger, including after later command replacements.
  v_proc := to_regprocedure('public.create_trip_round_v1(uuid,jsonb,uuid)');
  if v_proc is null then
    raise exception 'native round creation command is missing';
  end if;
  v_source := regexp_replace(
    lower(pg_get_functiondef(v_proc::oid)),
    '[[:space:]]+',
    ' ',
    'g'
  );
  if position(
    'coalesce(nullif(p_input->>''walkride'', ''''), ''ride''), null, p_trip_id'
    in v_source
  ) = 0 then
    raise exception 'native round creation still populates legacy rounds.created_by';
  end if;

  v_proc := to_regprocedure('public.convert_legacy_round_v1(uuid,text,uuid)');
  if v_proc is null then
    raise exception 'legacy conversion command is missing';
  end if;
  v_source := regexp_replace(
    lower(pg_get_functiondef(v_proc::oid)),
    '[[:space:]]+',
    ' ',
    'g'
  );
  if position('coalesce(rr.response::text, ''pending'')' in v_source) = 0
     or position('v_legacy.walk_ride, null, v_trip.id' in v_source) = 0 then
    raise exception 'legacy conversion is incompatible with production RSVP/creator types';
  end if;

  v_proc := to_regprocedure('public.create_creator_response()');
  if v_proc is null then
    raise exception 'legacy creator-response trigger function is missing';
  end if;
  if (select p.prosecdef from pg_proc p where p.oid = v_proc::oid) is distinct from true
     or not exists (
       select 1
       from pg_proc p,
       unnest(coalesce(p.proconfig, array[]::text[])) setting
       where p.oid = v_proc::oid and setting like 'search_path=%'
     )
     or has_function_privilege('authenticated', v_proc, 'EXECUTE') then
    raise exception 'legacy creator-response trigger execution boundary is unsafe';
  end if;
  v_source := lower(pg_get_functiondef(v_proc::oid));
  if position('new.trip_id is not null' in v_source) = 0
     or position('new.created_by is null' in v_source) = 0 then
    raise exception 'legacy creator-response trigger is not guarded from native rounds';
  end if;

  v_proc := to_regprocedure('public.lock_round_if_ready()');
  if v_proc is null then
    raise exception 'legacy round-lock trigger function is missing';
  end if;
  if (select p.prosecdef from pg_proc p where p.oid = v_proc::oid) is distinct from false
     or not exists (
       select 1
       from pg_proc p,
       unnest(coalesce(p.proconfig, array[]::text[])) setting
       where p.oid = v_proc::oid and setting like 'search_path=%'
     )
     or has_function_privilege('authenticated', v_proc, 'EXECUTE') then
    raise exception 'legacy round-lock trigger execution boundary is unsafe';
  end if;
  v_source := regexp_replace(
    lower(pg_get_functiondef(v_proc::oid)),
    '[[:space:]]+',
    ' ',
    'g'
  );
  if position('select r.trip_id into v_trip_id' in v_source) = 0
     or position('v_trip_id is not null' in v_source) = 0
     or position('rr.response = ''yes''' in v_source) = 0
     or position(') >= 2 then' in v_source) = 0 then
    raise exception 'legacy round-lock trigger no longer preserves guarded two-yes semantics';
  end if;

  v_proc := to_regprocedure('public.invite_friend_to_round(uuid,uuid)');
  if v_proc is null then
    raise exception 'legacy friend invitation command is missing';
  end if;
  if (select p.prosecdef from pg_proc p where p.oid = v_proc::oid) is distinct from true
     or not exists (
       select 1
       from pg_proc p,
       unnest(coalesce(p.proconfig, array[]::text[])) setting
       where p.oid = v_proc::oid and setting like 'search_path=%'
     )
     or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
     or has_function_privilege('anon', v_proc, 'EXECUTE') then
    raise exception 'legacy friend invitation command privileges are unsafe';
  end if;
  v_source := pg_get_functiondef(v_proc::oid);
  if position('v_round.trip_id is not null' in lower(v_source)) = 0
     or position('v_round.created_by is distinct from v_user_id' in lower(v_source)) = 0
     or position('f.user_low = least(v_user_id, p_friend_id)' in lower(v_source)) = 0
     or position('f.user_high = greatest(v_user_id, p_friend_id)' in lower(v_source)) = 0
     or position('raise exception ''Not authenticated''' in v_source) = 0
     or position('raise exception ''Round not found''' in v_source) = 0
     or position('raise exception ''Only the creator can invite''' in v_source) = 0
     or position('raise exception ''Not friends''' in v_source) = 0 then
    raise exception 'legacy friend invitation command changed its production contract';
  end if;

  if to_regclass('public.visible_rounds') is null then
    raise exception 'legacy visible_rounds view is missing';
  end if;
  select array_agg(a.attname::text order by a.attnum)
  into v_columns
  from pg_attribute a
  where a.attrelid = 'public.visible_rounds'::regclass
    and a.attnum > 0
    and not a.attisdropped;
  if v_columns is distinct from array[
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
  ]::text[]
     or position(
       'r.trip_id is null'
       in lower(pg_get_viewdef('public.visible_rounds'::regclass, true))
     ) = 0
     or not (
       select coalesce(c.reloptions, array[]::text[])
         @> array['security_invoker=true', 'security_barrier=true']::text[]
       from pg_class c
       where c.oid = 'public.visible_rounds'::regclass
     )
     or not has_table_privilege('authenticated', 'public.rounds', 'SELECT')
     or not has_table_privilege('authenticated', 'public.round_responses', 'SELECT')
     or not has_table_privilege('authenticated', 'public.visible_rounds', 'SELECT')
     or has_table_privilege('anon', 'public.visible_rounds', 'SELECT') then
    raise exception 'legacy visible_rounds shape or native-round filter is unsafe';
  end if;

  if not exists (
    select 1
    from pg_policy p
    where p.polrelid = 'public.rounds'::regclass
      and p.polname = 'Legacy round participants can read rounds'
      and p.polpermissive
      and p.polcmd = 'r'
      and p.polroles @> array['authenticated'::regrole::oid]
      and position(
        'current_user_has_legacy_round_response_v1'
        in pg_get_expr(p.polqual, p.polrelid)
      ) > 0
  ) then
    raise exception 'legacy participant round-read policy is missing or recursive';
  end if;

  select count(*) into v_flag_count
  from pg_class c
  where c.oid in (
    'public.rounds'::regclass,
    'public.round_responses'::regclass,
    'public.scorecards'::regclass,
    'public.scorecard_holes'::regclass,
    'public.handicap_differentials'::regclass
  )
    and c.relrowsecurity;
  if v_flag_count <> 5 then
    raise exception 'legacy hierarchy RLS is not enabled';
  end if;

  select count(*) into v_flag_count
  from pg_policy p
  where not p.polpermissive
    and p.polroles @> array['authenticated'::regrole::oid]
    and (
      (
        p.polrelid = 'public.rounds'::regclass
        and p.polname = 'Legacy boundary permits legacy or member round reads'
        and p.polcmd = 'r'
      )
      or (
        p.polrelid = 'public.round_responses'::regclass
        and p.polname = 'Legacy boundary blocks native round responses'
        and p.polcmd = '*'
      )
      or (
        p.polrelid = 'public.scorecards'::regclass
        and p.polname = 'Legacy boundary blocks native scorecards'
        and p.polcmd = '*'
      )
      or (
        p.polrelid = 'public.scorecard_holes'::regclass
        and p.polname = 'Legacy boundary blocks native scorecard holes'
        and p.polcmd = '*'
      )
      or (
        p.polrelid = 'public.handicap_differentials'::regclass
        and p.polname = 'Legacy boundary blocks native handicap differentials'
        and p.polcmd = '*'
      )
    );
  if v_flag_count <> 5 then
    raise exception 'native-parent isolation policies are missing or permissive';
  end if;

  foreach v_proc in array array[
    to_regprocedure('tee_internal.current_user_has_legacy_round_response_v1(uuid)'),
    to_regprocedure('tee_internal.round_is_legacy_v1(uuid)'),
    to_regprocedure('tee_internal.scorecard_is_legacy_v1(uuid)')
  ] loop
    if v_proc is null
       or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
       or has_function_privilege('anon', v_proc, 'EXECUTE')
       or (select p.prosecdef from pg_proc p where p.oid = v_proc::oid) is distinct from true
       or not exists (
         select 1
         from pg_proc p,
         unnest(coalesce(p.proconfig, array[]::text[])) setting
         where p.oid = v_proc::oid and setting like 'search_path=%'
       ) then
      raise exception 'legacy-parent RLS helper is unsafe: %', v_proc;
    end if;
  end loop;

  v_proc := to_regprocedure('public.release_trip_player_claim_v1(uuid)');
  if v_proc is null then
    raise exception 'roster claim release command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('native_writes_enabled' in v_source) = 0
     or position('claimed_user_id is distinct from v_user_id' in v_source) = 0
     or position('trip_role(v_player.trip_id, v_user_id) is distinct from ''captain''' in v_source) = 0 then
    raise exception 'roster claim release authorization or kill-switch boundary is nullable';
  end if;

  v_proc := to_regprocedure('public.set_trip_status_v1(uuid,text,text)');
  if v_proc is null then
    raise exception 'trip lifecycle command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_expected_status is null or p_new_status is null' in v_source) = 0
     or position('v_trip.status is distinct from p_expected_status' in v_source) = 0 then
    raise exception 'trip lifecycle command has nullable transition semantics';
  end if;

  v_proc := to_regprocedure('public.set_trip_round_status_v1(uuid,text,text,boolean)');
  if v_proc is null then
    raise exception 'round lifecycle command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_expected_status is null or p_new_status is null' in v_source) = 0
     or position('p_allow_incomplete is null' in v_source) = 0
     or position('v_current_status is distinct from p_expected_status' in v_source) = 0
     or position('v_trip.status is distinct from ''live''' in v_source) = 0 then
    raise exception 'round lifecycle command has nullable transition semantics';
  end if;

  v_proc := to_regprocedure('public.advance_trip_round_v1(uuid,uuid,bigint,boolean)');
  if v_proc is null then
    raise exception 'trip advance wrapper is missing';
  end if;
  if position('p_allow_incomplete is null' in lower(pg_get_functiondef(v_proc::oid))) = 0 then
    raise exception 'trip advance wrapper accepts NULL allowIncomplete';
  end if;

  v_proc := to_regprocedure('tee_internal.advance_trip_round_unfiltered_v1(uuid,uuid,bigint,boolean)');
  if v_proc is null then
    raise exception 'unfiltered trip advance command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_allow_incomplete is null' in v_source) = 0
     or position('not coalesce(p_allow_incomplete, false)' in v_source) = 0
     or position('v_trip.status is distinct from ''live''' in v_source) = 0
     or position('v_current_status is distinct from ''live''' in v_source) = 0
     or position('r.trip_round_status is distinct from ''completed''' in v_source) = 0 then
    raise exception 'unfiltered trip advance command can fail open on NULL state';
  end if;

  v_proc := to_regprocedure('tee_internal.start_trip_unfiltered_v1(uuid,bigint)');
  if v_proc is null then
    raise exception 'unfiltered trip start command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('v_trip.status is distinct from ''ready''' in v_source) = 0
     or position('r.trip_round_status is distinct from ''scheduled''' in v_source) = 0 then
    raise exception 'unfiltered trip start command can accept NULL lifecycle state';
  end if;

  foreach v_proc in array array[
    to_regprocedure('tee_internal.record_hole_score_unfiltered_v1(uuid,uuid,smallint,smallint,smallint,uuid,bigint)'),
    to_regprocedure('tee_internal.record_extension_hole_score_unfiltered_service_v1(text,uuid,uuid,smallint,smallint,smallint,uuid,bigint)')
  ] loop
    if v_proc is null then
      raise exception 'unfiltered score command is missing';
    end if;
    v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
    if position('v_trip.status is distinct from ''live''' in v_source) = 0
       or position('v_round_status is distinct from ''live''' in v_source) = 0 then
      raise exception 'unfiltered score command can accept NULL lifecycle state: %', v_proc;
    end if;
  end loop;

  v_proc := to_regprocedure('tee_internal.record_extension_hole_score_unfiltered_service_v1(text,uuid,uuid,smallint,smallint,smallint,uuid,bigint)');
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_trip_player_id is distinct from v_session.trip_player_id' in v_source) = 0
     or position('v_round_trip_id is distinct from v_session.trip_id' in v_source) = 0 then
    raise exception 'Messages score identity comparisons are nullable';
  end if;

  v_proc := to_regprocedure('public.persist_trip_snapshot_v1(uuid,bigint,jsonb,text)');
  if v_proc is null then
    raise exception 'snapshot persistence command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_revision is null' in v_source) = 0
     or position('v_trip.score_revision is distinct from p_revision' in v_source) = 0
     or position('p_payload is null' in v_source) = 0
     or position('jsonb_typeof(p_payload) is distinct from ''object''' in v_source) = 0
     or position('p_scoring_engine_version is distinct from ''tee-circle-ts-2''' in v_source) = 0 then
    raise exception 'canonical snapshot validation can fail open on NULL fields';
  end if;

  foreach v_proc in array array[
    to_regprocedure('public.lease_trip_snapshot_jobs_v1(integer)'),
    to_regprocedure('public.lease_live_activity_deliveries_service_v1(uuid,bigint,integer)')
  ] loop
    if v_proc is null
       or position('p_limit is null' in lower(pg_get_functiondef(v_proc::oid))) = 0 then
      raise exception 'worker lease accepts a NULL/unbounded limit: %', v_proc;
    end if;
  end loop;

  v_proc := to_regprocedure('tee_internal.consume_public_rate_limit_v1(bytea,text,integer,integer)');
  if v_proc is null then
    raise exception 'public rate limiter is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_limit is null' in v_source) = 0
     or position('p_window_seconds is null' in v_source) = 0 then
    raise exception 'public rate limiter accepts NULL bounds';
  end if;

  v_proc := to_regprocedure('public.complete_live_activity_delivery_service_v1(uuid,bigint,uuid,text,boolean)');
  if v_proc is null then
    raise exception 'Live Activity completion command is missing';
  end if;
  v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
  if position('p_subscription_id is null' in v_source) = 0
     or position('p_revision is null' in v_source) = 0
     or position('p_outcome is null' in v_source) = 0
     or position('p_is_final is null' in v_source) = 0 then
    raise exception 'Live Activity completion accepts NULL required values';
  end if;

  v_proc := to_regprocedure('public.register_device_push_v1(text,text,text,text)');
  if v_proc is null
     or position(
       'p_bundle_id is distinct from ''com.teecircle.app'''
       in lower(pg_get_functiondef(v_proc::oid))
     ) = 0 then
    raise exception 'APNs registration accepts a NULL bundle identifier';
  end if;

  foreach v_proc in array array[
    to_regprocedure('public.update_trip_round_v1(uuid,jsonb,timestamptz)'),
    to_regprocedure('public.delete_trip_round_v1(uuid,uuid,timestamptz)')
  ] loop
    if v_proc is null then
      raise exception 'native round edit command is missing';
    end if;
    v_source := regexp_replace(lower(pg_get_functiondef(v_proc::oid)), '[[:space:]]+', ' ', 'g');
    if position('v_round.native_updated_at is distinct from p_expected_native_updated_at' in v_source) = 0
       or position('v_round.trip_round_status is distinct from ''scheduled''' in v_source) = 0 then
      raise exception 'native round edit command has nullable optimistic/lifecycle state: %', v_proc;
    end if;
  end loop;

  select count(*) into v_flag_count from tee_internal.runtime_flags
  where (key, enabled) in (
    ('native_writes_enabled', false),
    ('public_previews_enabled', false),
    ('live_activity_pushes_enabled', false),
    ('purchases_required', true),
    ('sandbox_purchases_enabled', false)
  );
  if v_flag_count <> 5 then
    raise exception 'runtime flags are not deterministic';
  end if;

  if not exists (
    select 1
    from pg_publication p
    where p.pubname = 'supabase_realtime'
      and not p.puballtables
  ) or not exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime'
      and pr.prrelid = 'public.trip_leaderboard_snapshots'::regclass
  ) then
    raise exception 'safe supabase_realtime snapshot publication is missing';
  end if;
  if exists (
    select 1
    from pg_publication p
    left join pg_publication_rel pr on pr.prpubid = p.oid
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
  ) or exists (
    select 1
    from pg_publication p
    join pg_publication_rel pr on pr.prpubid = p.oid
    where p.pubname = 'supabase_realtime'
      and pr.prrelid <> 'public.trip_leaderboard_snapshots'::regclass
  ) then
    raise exception 'Realtime publication exposes a legacy or unexpected table';
  end if;
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'public.trip_hole_scores'::regclass
      and c.conname = 'trip_hole_scores_round_player_fkey'
      and c.confdeltype = 'r'
  ) then
    raise exception 'score round/player FK does not restrict destructive cascades';
  end if;
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'public.rounds'::regclass
      and c.conname = 'rounds_trip_id_fkey'
      and c.confdeltype = 'r'
  ) then
    raise exception 'native rounds can be orphaned into legacy data by trip deletion';
  end if;
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'public.rounds'::regclass
      and c.conname = 'rounds_legacy_source_round_id_fkey'
      and c.confdeltype = 'n'
  ) then
    raise exception 'legacy source deletion no longer uses the intended set-null behavior';
  end if;
  if exists (
    select 1 from pg_attribute a
    where a.attrelid in (
      'public.trips'::regclass,
      'public.trip_hole_scores'::regclass,
      'public.trip_score_audit'::regclass,
      'public.trip_invites'::regclass,
      'public.trip_purchase_intents'::regclass
    )
      and a.attname in ('owner_id', 'recorded_by_user_id', 'actor_user_id', 'created_by', 'user_id')
      and not a.attnotnull
  ) then
    raise exception 'account-attribution columns were unsafely made nullable';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'tee_internal')
      and regexp_replace(
        lower(p.prosrc),
        '[[:space:]]+',
        ' ',
        'g'
      ) ~ 'tee_internal[.]trip_role[(][^;]*[)][ ]*(<>|!=)[ ]*''captain'''
  ) then
    raise exception 'a captain command uses a nullable trip_role inequality';
  end if;

  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef
      and n.nspname in ('public', 'tee_internal')
      and (p.proname like '%_v1' or p.proname like '%_service_v1')
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) setting
        where setting like 'search_path=%'
      )
  ) then
    raise exception 'a v1 SECURITY DEFINER function has no pinned search_path';
  end if;
end
$$;

rollback;
