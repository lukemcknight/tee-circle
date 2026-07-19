set lock_timeout = '10s';
set statement_timeout = '5min';

-- Authenticated reusable course-card read model for native trip creation.


create or replace function public.get_course_cards_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_cards jsonb;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cc.id,
        'name', cc.name,
        'courseName', cc.course_name,
        'holeCount', cc.hole_count,
        'createdAt', cc.created_at,
        'updatedAt', cc.updated_at,
        'holes', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'holeNumber', cch.hole_number,
                'par', cch.par,
                'strokeIndex', cch.stroke_index,
                'yards', cch.yards
              ) order by cch.hole_number
            )
            from public.course_card_holes cch
            where cch.course_card_id = cc.id
          ),
          '[]'::jsonb
        )
      ) order by cc.updated_at desc, cc.created_at desc, cc.id
    ),
    '[]'::jsonb
  ) into v_cards
  from public.course_cards cc
  where cc.owner_id = v_user_id
    and cc.archived_at is null;

  return tee_internal.api_success(
    v_request_id,
    jsonb_build_object('courseCards', v_cards)
  );
end;
$$;

revoke all on function public.get_course_cards_v1() from public;
grant execute on function public.get_course_cards_v1() to authenticated;
