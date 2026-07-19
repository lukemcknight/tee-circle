-- Run immediately after the no-op legacy baseline marker and before migration
-- 001. These checks ensure the marker left the reviewed production-shaped
-- fixture intact and did not partially install native-v2 objects.

begin;

do $$
declare
  v_columns text[];
  v_enum_labels text[];
  v_native_relation text;
begin
  select array_agg(a.attname::text order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.rounds'::regclass
    and a.attnum > 0
    and not a.attisdropped;
  if v_columns is distinct from array[
    'id', 'group_id', 'course_name', 'tee_time', 'holes', 'walk_ride',
    'status', 'created_by', 'created_at', 'course_place_id',
    'course_address', 'course_lat', 'course_lng'
  ]::text[] then
    raise exception 'baseline marker changed public.rounds: %', v_columns;
  end if;

  select array_agg(a.attname::text order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.round_responses'::regclass
    and a.attnum > 0
    and not a.attisdropped;
  if v_columns is distinct from array[
    'round_id', 'user_id', 'response', 'responded_at'
  ]::text[] then
    raise exception 'baseline marker changed public.round_responses: %', v_columns;
  end if;

  select array_agg(e.enumlabel::text order by e.enumsortorder)
    into v_enum_labels
  from pg_catalog.pg_enum e
  where e.enumtypid = 'public.round_status'::regtype;
  if v_enum_labels is distinct from array['open', 'locked']::text[] then
    raise exception 'baseline marker changed public.round_status: %', v_enum_labels;
  end if;

  select array_agg(e.enumlabel::text order by e.enumsortorder)
    into v_enum_labels
  from pg_catalog.pg_enum e
  where e.enumtypid = 'public.response_status'::regtype;
  if v_enum_labels is distinct from array['yes', 'no', 'pending']::text[] then
    raise exception 'baseline marker changed public.response_status: %', v_enum_labels;
  end if;

  if (
    select count(*)
    from pg_catalog.pg_class c
    where c.oid in (
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
      and c.relrowsecurity
  ) <> 10 then
    raise exception 'baseline marker changed legacy RLS enablement';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_attribute source_attribute
      on source_attribute.attrelid = con.conrelid
     and source_attribute.attnum = con.conkey[1]
    where con.contype = 'f'
      and con.conrelid = 'public.rounds'::regclass
      and con.confrelid = 'public.profiles'::regclass
      and source_attribute.attname = 'created_by'
      and con.confdeltype = 'a'
  ) or not exists (
    select 1
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_attribute source_attribute
      on source_attribute.attrelid = con.conrelid
     and source_attribute.attnum = con.conkey[1]
    where con.contype = 'f'
      and con.conrelid = 'public.round_responses'::regclass
      and con.confrelid = 'public.profiles'::regclass
      and source_attribute.attname = 'user_id'
      and con.confdeltype = 'c'
  ) then
    raise exception 'baseline marker changed profile-backed round foreign keys';
  end if;

  if to_regprocedure('public.create_creator_response()') is null
     or to_regprocedure('public.lock_round_if_ready()') is null
     or to_regprocedure('public.invite_friend_to_round(uuid,uuid)') is null
     or not exists (
       select 1
       from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.rounds'::regclass
         and t.tgname = 'on_round_created_add_creator_response'
         and not t.tgisinternal
         and t.tgenabled <> 'D'
     )
     or not exists (
       select 1
       from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.round_responses'::regclass
         and t.tgname = 'check_round_lock'
         and not t.tgisinternal
         and t.tgenabled <> 'D'
         and lower(pg_get_triggerdef(t.oid, true)) like '%after update on round_responses%'
     ) then
    raise exception 'baseline marker changed legacy trigger/function wiring';
  end if;

  select array_agg(a.attname::text order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.visible_rounds'::regclass
    and a.attnum > 0
    and not a.attisdropped;
  if v_columns is distinct from array[
    'id', 'group_id', 'course_name', 'course_place_id', 'course_address',
    'course_lat', 'course_lng', 'tee_time', 'holes', 'walk_ride', 'status',
    'created_by', 'created_at'
  ]::text[]
     or position(
       'trip_id'
       in lower(pg_get_viewdef('public.visible_rounds'::regclass, true))
     ) <> 0 then
    raise exception 'baseline marker changed public.visible_rounds';
  end if;

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
  ) or exists (
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
    raise exception 'baseline marker changed audited Realtime publication state';
  end if;

  if to_regnamespace('tee_internal') is not null then
    raise exception 'baseline marker created tee_internal';
  end if;

  if to_regprocedure('public.delete_round(uuid)') is not null then
    raise exception 'baseline marker created unaudited public.delete_round(uuid)';
  end if;

  foreach v_native_relation in array array[
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
    if to_regclass(v_native_relation) is not null then
      raise exception 'baseline marker created native relation %', v_native_relation;
    end if;
  end loop;
end
$$;

rollback;
