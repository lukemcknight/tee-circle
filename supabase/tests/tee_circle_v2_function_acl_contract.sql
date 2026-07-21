begin;

do $$
declare
  v_signature text;
  v_expected_authenticated text[] := array[
    'public.accept_trip_invite_v1(text,uuid)',
    'public.add_trip_player_v1(uuid,jsonb,uuid)',
    'public.advance_trip_round_v1(uuid,uuid,bigint,boolean)',
    'public.cancel_trip_purchase_intent_v1(uuid)',
    'public.convert_legacy_round_v1(uuid,text,uuid)',
    'public.create_course_card_v1(jsonb,uuid)',
    'public.create_trip_invite_v1(uuid,timestamp with time zone,integer,uuid)',
    'public.create_trip_purchase_intent_v1(uuid,uuid)',
    'public.create_trip_round_v1(uuid,jsonb,uuid)',
    'public.create_trip_v1(jsonb,uuid)',
    'public.delete_round(uuid)',
    'public.delete_trip_player_v1(uuid,uuid,timestamp with time zone)',
    'public.delete_trip_round_v1(uuid,uuid,timestamp with time zone)',
    'public.delete_user_account()',
    'public.end_live_activity_v1(text)',
    'public.finalize_account_deletion_v1()',
    'public.get_account_deletion_blockers_v1()',
    'public.get_course_cards_v1()',
    'public.get_legacy_rounds_v1()',
    'public.get_my_trips_v1()',
    'public.get_trip_bootstrap_v1(uuid)',
    'public.issue_extension_session_v1(uuid,text)',
    'public.list_trip_invites_v1(uuid)',
    'public.register_device_push_v1(text,text,text,text)',
    'public.register_live_activity_v1(uuid,text,text,text,text,timestamp with time zone)',
    'public.release_trip_player_claim_v1(uuid)',
    'public.revoke_extension_session_v1(uuid)',
    'public.revoke_trip_invite_v1(uuid)',
    'public.rotate_trip_invite_v1(uuid,timestamp with time zone,integer,uuid)',
    'public.set_round_participation_v1(uuid,uuid,smallint,smallint,text)',
    'public.set_trip_status_v1(uuid,text,text)',
    'public.start_trip_v1(uuid,bigint)',
    'public.transfer_trip_ownership_v1(uuid,uuid)',
    'public.unregister_device_push_v1(text,text,text)',
    'public.update_course_card_v1(uuid,jsonb,timestamp with time zone)',
    'public.update_trip_player_v1(uuid,jsonb)',
    'public.update_trip_round_v1(uuid,jsonb,timestamp with time zone)',
    'public.update_trip_v1(uuid,jsonb,timestamp with time zone)'
  ];
  v_expected_service text[] := array[
    'public.complete_live_activity_delivery_service_v1(uuid,bigint,uuid,text,boolean)',
    'public.consume_public_rate_limit_service_v1(text,text,integer,integer)',
    'public.enqueue_missing_trip_snapshot_jobs_service_v1()',
    'public.fail_trip_snapshot_job_v1(uuid,bigint,text)',
    'public.get_latest_activity_snapshots_service_v1(uuid[],bigint)',
    'public.get_messages_bootstrap_service_v1(text)',
    'public.get_runtime_flag_service_v1(text)',
    'public.get_trip_scoring_input_v1(uuid,bigint)',
    'public.lease_live_activity_deliveries_service_v1(uuid,bigint,integer)',
    'public.lease_trip_snapshot_jobs_v1(integer)',
    'public.persist_trip_snapshot_v1(uuid,bigint,jsonb,text)',
    'public.record_authenticated_hole_score_service_v1(uuid,uuid,uuid,smallint,smallint,smallint,uuid,bigint)',
    'public.record_extension_hole_score_service_v1(text,uuid,uuid,smallint,smallint,smallint,uuid,bigint)',
    'public.resolve_extension_session_service_v1(text)',
    'public.resolve_public_trip_preview_service_v1(text)',
    'public.verify_trip_purchase_v1(uuid,text,text,text,timestamp with time zone,timestamp with time zone)'
  ];
begin
  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where (
      n.nspname = 'tee_internal'
      or (
        n.nspname = 'public'
        and (p.proname like '%\_v1' escape '\' or p.proname in ('delete_round', 'delete_user_account'))
      )
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'anon can execute a native/private function';
  end if;

  foreach v_signature in array v_expected_authenticated loop
    if to_regprocedure(v_signature) is null
       or not has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'authenticated RPC ACL mismatch: %', v_signature;
    end if;
  end loop;

  foreach v_signature in array v_expected_service loop
    if to_regprocedure(v_signature) is null
       or not has_function_privilege('service_role', v_signature, 'EXECUTE')
       or has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'service RPC ACL mismatch: %', v_signature;
    end if;
  end loop;

  if has_function_privilege('authenticated', 'public.claim_trip_player_v1(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.claim_trip_player_v1(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.record_hole_score_v1(uuid,uuid,smallint,smallint,smallint,uuid,bigint)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.record_hole_score_v1(uuid,uuid,smallint,smallint,smallint,uuid,bigint)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.set_trip_round_status_v1(uuid,text,text,boolean)', 'EXECUTE') then
    raise exception 'private native primitive is executable by an API role';
  end if;
end
$$;

rollback;
