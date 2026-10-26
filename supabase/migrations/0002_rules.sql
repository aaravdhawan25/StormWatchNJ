-- StormWatch NJ, the rules, as functions

-- ---- accounts

-- the township a given email address belongs to, or null
create or replace function public.township_for_email(p_email text)
returns text
language sql stable security definer set search_path = ''
as $$
    select d.name
      from public.township_domains d
     where d.domain = lower(substring(trim(p_email) from '@([^@]+)$'))
       and trim(p_email) ~ '^[^@\s]+@[^@\s]+$';
$$;

-- block township sign-ups from non-town emails
create or replace function public.check_township_signup()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    if coalesce(new.raw_user_meta_data ->> 'account_type', 'resident') = 'township'
       and public.township_for_email(new.email) is null then
        raise exception 'That email is not on a recognised township domain.'
            using errcode = 'P0001';
    end if;
    return new;
end;
$$;

-- keeps profiles.role in step with the account
create or replace function public.sync_profile()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    v_township text := public.township_for_email(new.email);
    v_is_township boolean :=
        coalesce(new.raw_user_meta_data ->> 'account_type', 'resident') = 'township'
        and v_township is not null
        and new.email_confirmed_at is not null;
begin
    insert into public.profiles (id, role, township)
    values (new.id,
            case when v_is_township then 'township' else 'resident' end,
            case when v_is_township then v_township end)
    on conflict (id) do update
       set role = excluded.role, township = excluded.township, updated_at = now();
    return new;
end;
$$;

create trigger stormwatch_check_township_signup
    before insert on auth.users
    for each row execute function public.check_township_signup();

create trigger stormwatch_sync_profile
    after insert or update of email, email_confirmed_at, raw_user_meta_data on auth.users
    for each row execute function public.sync_profile();

create or replace function public.is_township()
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (select 1 from public.profiles p
                    where p.id = (select auth.uid()) and p.role = 'township');
$$;

-- ---- hazards

-- the shared hazard list as the caller should see it
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
     order by h.created_at desc
     limit 1000;
$$;

-- files a report
create or replace function public.report_hazard(
    p_report_type text, p_severity text, p_road_status text,
    p_utility_lines_involved boolean, p_description text,
    p_latitude double precision, p_longitude double precision,
    p_address text default null, p_zipcode text default null, p_municipality text default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_point extensions.geography :=
        extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;
    v_existing uuid;
    v_id uuid;
begin
    if p_latitude is null or p_longitude is null
       or p_latitude not between 38.86 and 41.40 or p_longitude not between -75.61 and -73.88 then
        raise exception 'Location is outside New Jersey, the service area.' using errcode = 'P0001';
    end if;

    select h.id into v_existing
      from public.hazards h
     where h.report_type = p_report_type
       and h.status <> 'RESOLVED'
       and h.created_at > now() - interval '6 hours'
       and extensions.st_dwithin(h.location, v_point, 75)
     order by h.created_at
     limit 1;

    if v_existing is not null then
        update public.hazards set upvotes = upvotes + 1, updated_at = now() where id = v_existing;
        return jsonb_build_object('id', v_existing, 'duplicate', true);
    end if;

    insert into public.hazards (report_type, severity, road_status, utility_lines_involved,
                                description, latitude, longitude, address, zipcode, municipality, owner_id)
    values (p_report_type, p_severity, p_road_status,
            coalesce(p_utility_lines_involved, false) or p_report_type = 'DOWNED_WIRE',
            trim(p_description), p_latitude, p_longitude,
            nullif(trim(p_address), ''), nullif(trim(p_zipcode), ''), nullif(trim(p_municipality), ''),
            (select auth.uid()))
    returning id into v_id;

    return jsonb_build_object('id', v_id, 'duplicate', false);
end;
$$;

create or replace function public.archive_and_delete_hazard(p_hazard uuid, p_reason text, p_by uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.removed_hazards (id, report_type, latitude, longitude, created_at, reason, removed_by)
    select h.id, h.report_type, h.latitude, h.longitude, h.created_at, p_reason, p_by
      from public.hazards h where h.id = p_hazard
    on conflict (id) do nothing;
    delete from public.hazards where id = p_hazard;
end;
$$;

-- "it's not there anymore": one vote each, third vote removes it
create or replace function public.vote_not_there(p_hazard uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := (select auth.uid());
    v_owner uuid;
    v_count integer;
    c_threshold constant integer := 3;
begin
    if v_uid is null then
        raise exception 'Sign in to do that.' using errcode = '42501';
    end if;

    -- lock the hazard so two simultaneous third votes cannot both act on it
    select h.owner_id into v_owner from public.hazards h where h.id = p_hazard for update;
    if not found then
        raise exception 'That hazard is no longer on the map.' using errcode = 'P0002';
    end if;
    if v_owner = v_uid then
        raise exception 'You reported this hazard — remove it instead of voting.' using errcode = 'P0001';
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

-- removal by the reporter or by township staff
create or replace function public.remove_hazard(p_hazard uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := (select auth.uid());
    v_owner uuid;
    v_reason text;
begin
    if v_uid is null then
        raise exception 'Sign in to do that.' using errcode = '42501';
    end if;
    select h.owner_id into v_owner from public.hazards h where h.id = p_hazard for update;
    if not found then
        raise exception 'That hazard is no longer on the map.' using errcode = 'P0002';
    end if;

    if public.is_township() then
        v_reason := 'township';
    elsif v_owner = v_uid then
        v_reason := 'reporter';
    else
        raise exception 'Only the person who reported this, or a township account, can remove it.'
            using errcode = '42501';
    end if;

    perform public.archive_and_delete_hazard(p_hazard, v_reason, v_uid);
    return jsonb_build_object('removed', true);
end;
$$;

create or replace function public.set_hazard_status(p_hazard uuid, p_status text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
    if not public.is_township() then
        raise exception 'Only township accounts can change crew status.' using errcode = '42501';
    end if;
    update public.hazards set status = p_status, updated_at = now() where id = p_hazard;
    if not found then
        raise exception 'That hazard is no longer on the map.' using errcode = 'P0002';
    end if;
    return jsonb_build_object('status', p_status);
end;
$$;

-- ---- permissions

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.township_for_email(text) to anon, authenticated, service_role;
grant execute on function public.list_hazards()           to authenticated, service_role;
grant execute on function public.report_hazard(text, text, text, boolean, text,
        double precision, double precision, text, text, text) to authenticated, service_role;
grant execute on function public.vote_not_there(uuid)          to authenticated;
grant execute on function public.remove_hazard(uuid)           to authenticated;
grant execute on function public.set_hazard_status(uuid, text) to authenticated;
-- helpers are only called by the functions above
grant execute on function public.check_township_signup() to supabase_auth_admin;
grant execute on function public.sync_profile()          to supabase_auth_admin;
grant execute on function public.is_township()           to authenticated;

-- functions created later should not be open by default either
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
