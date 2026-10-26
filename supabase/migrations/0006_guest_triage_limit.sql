-- the website's guest demo can use OpenAI photo analysis too, without an account

create table public.guest_triage_uses (
    id         bigint generated always as identity primary key,
    visitor    text        not null,
    created_at timestamptz not null default now()
);
create index guest_triage_uses_visitor_time on public.guest_triage_uses (visitor, created_at);
create index guest_triage_uses_time on public.guest_triage_uses (created_at);

-- server only: row level security with no policies
alter table public.guest_triage_uses enable row level security;
revoke all on public.guest_triage_uses from anon, authenticated;

-- counts and records one guest use atomically
create or replace function public.claim_guest_triage(p_visitor text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    c_per_visitor_hour constant integer := 10;
    c_site_per_day     constant integer := 300;
begin
    -- one claim at a time, so two requests can't both slip under a limit
    perform pg_advisory_xact_lock(hashtext('guest_triage'));

    if (select count(*) from public.guest_triage_uses
         where visitor = p_visitor and created_at > now() - interval '1 hour') >= c_per_visitor_hour then
        return 'visitor';
    end if;
    if (select count(*) from public.guest_triage_uses
         where created_at > now() - interval '1 day') >= c_site_per_day then
        return 'site';
    end if;

    insert into public.guest_triage_uses (visitor) values (p_visitor);
    -- old rows are only needed for the rolling day
    delete from public.guest_triage_uses where created_at < now() - interval '2 days';
    return 'ok';
end;
$$;
revoke execute on function public.claim_guest_triage(text) from public, anon, authenticated;
grant execute on function public.claim_guest_triage(text) to service_role;
