-- hazards expire after 3 days, and votes only count within 1 mile

alter table public.removed_hazards drop constraint removed_hazards_reason_check;
alter table public.removed_hazards add constraint removed_hazards_reason_check
    check (reason in ('reporter', 'township', 'community', 'expired'));

-- ---- expiry

-- archives and deletes every hazard with no activity for 3 days
create or replace function public.expire_hazards()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
    v_id uuid;
    v_count integer := 0;
begin
    for v_id in
        select h.id from public.hazards h
         where h.updated_at < now() - interval '3 days'
           for update skip locked
    loop
        perform public.archive_and_delete_hazard(v_id, 'expired', null);
        v_count := v_count + 1;
    end loop;
    return v_count;
end;
$$;
revoke execute on function public.expire_hazards() from public, anon, authenticated;

-- the app's list also hides expired hazards
create or replace function public.list_hazards()
returns table (
    id uuid, report_type text, severity text, road_status text,
    utility_lines_involved boolean, description text, municipality text,
    address text, zipcode text, latitude double precision, longitude double precision,
    status text, upvotes integer, created_at timestamptz, updated_at timestamptz,
    not_there_votes integer, i_voted_not_there boolean, is_mine boolean
)
language sql stable security definer set search_path = ''
as $$
    select h.id, h.report_type, h.severity, h.road_status, h.utility_lines_involved,
           h.description, h.municipality, h.address, h.zipcode, h.latitude, h.longitude,
           h.status, h.upvotes, h.created_at, h.updated_at,
           (select count(*)::integer from public.hazard_votes v where v.hazard_id = h.id),
           exists (select 1 from public.hazard_votes v
                    where v.hazard_id = h.id and v.user_id = (select auth.uid())),
           h.owner_id is not null and h.owner_id = (select auth.uid())
      from public.hazards h
     where h.updated_at >= now() - interval '3 days'
     order by h.created_at desc
     limit 1000;
$$;

create extension if not exists pg_cron;
select cron.schedule('expire-hazards', '*/15 * * * *', 'select public.expire_hazards()');

-- ---- vote distance

-- the old version took no location
drop function if exists public.vote_not_there(uuid);

create or replace function public.vote_not_there(
    p_hazard uuid, p_latitude double precision, p_longitude double precision
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := (select auth.uid());
    v_owner uuid;
    v_near boolean;
    v_count integer;
    c_threshold constant integer := 3;
    c_max_meters constant double precision := 1609.344;   -- 1 mile
begin
    if v_uid is null then
        raise exception 'Sign in to do that.' using errcode = '42501';
    end if;
    if p_latitude is null or p_longitude is null
       or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
        raise exception 'Turn on location to vote. You need to be within 1 mile of the hazard.'
            using errcode = 'P0001';
    end if;

    -- lock the hazard so two simultaneous third votes cannot both act on it
    select h.owner_id,
           extensions.st_dwithin(h.location,
               extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography,
               c_max_meters)
      into v_owner, v_near
      from public.hazards h where h.id = p_hazard
       for update;
    if not found then
        raise exception 'That hazard is no longer on the map.' using errcode = 'P0002';
    end if;
    if v_owner = v_uid then
        raise exception 'You reported this hazard — remove it instead of voting.' using errcode = 'P0001';
    end if;
    if not v_near then
        raise exception 'You need to be within 1 mile of this hazard to vote that it''s gone.'
            using errcode = 'P0001';
    end if;

    insert into public.hazard_votes (hazard_id, user_id) values (p_hazard, v_uid)
    on conflict do nothing;
    select count(*) into v_count from public.hazard_votes v where v.hazard_id = p_hazard;

    if v_count >= c_threshold then
        perform public.archive_and_delete_hazard(p_hazard, 'community', null);
    end if;
    return jsonb_build_object('removed', v_count >= c_threshold,
                              'not_there_votes', v_count, 'not_there_threshold', c_threshold);
end;
$$;
revoke execute on function public.vote_not_there(uuid, double precision, double precision) from public, anon;
grant execute on function public.vote_not_there(uuid, double precision, double precision) to authenticated;
