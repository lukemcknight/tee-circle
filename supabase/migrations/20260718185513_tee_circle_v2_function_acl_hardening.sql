set lock_timeout = '10s';
set statement_timeout = '5min';

-- Hosted Supabase gives anon/authenticated/service_role explicit EXECUTE
-- grants through postgres default privileges. Normalize the complete native
-- RPC surface after every CREATE OR REPLACE, then restore only the intended
-- authenticated and server-only entry points.

do $$
declare
  v_function record;
begin
  for v_function in
    select p.oid::regprocedure as signature
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'tee_internal'
       or (
         n.nspname = 'public'
         and (
           p.proname like '%\_v1' escape '\'
           or p.proname in ('delete_round', 'delete_user_account')
         )
       )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      v_function.signature
    );
  end loop;
end
$$;

-- Signed-in app and Expo commands/read models.
grant execute on function public.accept_trip_invite_v1(text, uuid) to authenticated;
grant execute on function public.add_trip_player_v1(uuid, jsonb, uuid) to authenticated;
grant execute on function public.advance_trip_round_v1(uuid, uuid, bigint, boolean) to authenticated;
grant execute on function public.cancel_trip_purchase_intent_v1(uuid) to authenticated;
grant execute on function public.convert_legacy_round_v1(uuid, text, uuid) to authenticated;
grant execute on function public.create_course_card_v1(jsonb, uuid) to authenticated;
grant execute on function public.create_trip_invite_v1(uuid, timestamptz, integer, uuid) to authenticated;
grant execute on function public.create_trip_purchase_intent_v1(uuid, uuid) to authenticated;
grant execute on function public.create_trip_round_v1(uuid, jsonb, uuid) to authenticated;
grant execute on function public.create_trip_v1(jsonb, uuid) to authenticated;
grant execute on function public.delete_round(uuid) to authenticated;
grant execute on function public.delete_trip_player_v1(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.delete_trip_round_v1(uuid, uuid, timestamptz) to authenticated;
grant execute on function public.delete_user_account() to authenticated;
grant execute on function public.end_live_activity_v1(text) to authenticated;
grant execute on function public.get_account_deletion_blockers_v1() to authenticated;
grant execute on function public.get_course_cards_v1() to authenticated;
grant execute on function public.get_legacy_rounds_v1() to authenticated;
grant execute on function public.get_my_trips_v1() to authenticated;
grant execute on function public.get_trip_bootstrap_v1(uuid) to authenticated;
grant execute on function public.issue_extension_session_v1(uuid, text) to authenticated;
grant execute on function public.list_trip_invites_v1(uuid) to authenticated;
grant execute on function public.register_device_push_v1(text, text, text, text) to authenticated;
grant execute on function public.register_live_activity_v1(uuid, text, text, text, text, timestamptz) to authenticated;
grant execute on function public.release_trip_player_claim_v1(uuid) to authenticated;
grant execute on function public.revoke_extension_session_v1(uuid) to authenticated;
grant execute on function public.revoke_trip_invite_v1(uuid) to authenticated;
grant execute on function public.rotate_trip_invite_v1(uuid, timestamptz, integer, uuid) to authenticated;
grant execute on function public.set_round_participation_v1(uuid, uuid, smallint, smallint, text) to authenticated;
grant execute on function public.set_trip_status_v1(uuid, text, text) to authenticated;
grant execute on function public.start_trip_v1(uuid, bigint) to authenticated;
grant execute on function public.transfer_trip_ownership_v1(uuid, uuid) to authenticated;
grant execute on function public.unregister_device_push_v1(text, text, text) to authenticated;
grant execute on function public.update_course_card_v1(uuid, jsonb, timestamptz) to authenticated;
grant execute on function public.update_trip_player_v1(uuid, jsonb) to authenticated;
grant execute on function public.update_trip_round_v1(uuid, jsonb, timestamptz) to authenticated;
grant execute on function public.update_trip_v1(uuid, jsonb, timestamptz) to authenticated;

-- Edge Function and worker entry points. These are never direct client RPCs.
grant execute on function public.complete_live_activity_delivery_service_v1(uuid, bigint, uuid, text, boolean) to service_role;
grant execute on function public.consume_public_rate_limit_service_v1(text, text, integer, integer) to service_role;
grant execute on function public.enqueue_missing_trip_snapshot_jobs_service_v1() to service_role;
grant execute on function public.fail_trip_snapshot_job_v1(uuid, bigint, text) to service_role;
grant execute on function public.get_latest_activity_snapshots_service_v1(uuid[], bigint) to service_role;
grant execute on function public.get_messages_bootstrap_service_v1(text) to service_role;
grant execute on function public.get_runtime_flag_service_v1(text) to service_role;
grant execute on function public.get_trip_scoring_input_v1(uuid, bigint) to service_role;
grant execute on function public.lease_live_activity_deliveries_service_v1(uuid, bigint, integer) to service_role;
grant execute on function public.lease_trip_snapshot_jobs_v1(integer) to service_role;
grant execute on function public.persist_trip_snapshot_v1(uuid, bigint, jsonb, text) to service_role;
grant execute on function public.record_authenticated_hole_score_service_v1(uuid, uuid, uuid, smallint, smallint, smallint, uuid, bigint) to service_role;
grant execute on function public.record_extension_hole_score_service_v1(text, uuid, uuid, smallint, smallint, smallint, uuid, bigint) to service_role;
grant execute on function public.resolve_extension_session_service_v1(text) to service_role;
grant execute on function public.resolve_public_trip_preview_service_v1(text) to service_role;
grant execute on function public.verify_trip_purchase_v1(uuid, text, text, text, timestamptz, timestamptz) to service_role;

-- RLS/auth-bound helpers and private service primitives.
grant execute on function tee_internal.is_trip_member(uuid, uuid) to service_role;
grant execute on function tee_internal.trip_role(uuid, uuid) to service_role;
grant execute on function tee_internal.can_manage_trip(uuid, uuid) to service_role;
grant execute on function tee_internal.can_score_player(uuid, uuid, uuid) to service_role;
grant execute on function tee_internal.current_user_is_trip_member(uuid) to authenticated, service_role;
grant execute on function tee_internal.current_user_trip_role(uuid) to authenticated, service_role;
grant execute on function tee_internal.current_user_can_manage_trip(uuid) to authenticated, service_role;
grant execute on function tee_internal.current_user_can_score_player(uuid, uuid) to authenticated, service_role;
grant execute on function tee_internal.current_user_has_legacy_round_response_v1(uuid) to authenticated;
grant execute on function tee_internal.round_is_legacy_v1(uuid) to authenticated;
grant execute on function tee_internal.scorecard_is_legacy_v1(uuid) to authenticated;
grant execute on function tee_internal.trip_readiness_issues(uuid) to authenticated, service_role;
grant execute on function tee_internal.resolve_public_trip_preview(bytea) to service_role;
grant execute on function tee_internal.consume_public_rate_limit_v1(bytea, text, integer, integer) to service_role;
grant execute on function tee_internal.resolve_extension_session_v1(bytea) to service_role;
grant execute on function tee_internal.enqueue_missing_trip_snapshot_jobs_v1() to service_role;
