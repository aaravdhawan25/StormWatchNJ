-- The website's guest demo can use OpenAI photo analysis too, without an
-- account. To keep strangers from running up the OpenAI bill, each guest
-- analysis is counted here and the analyze-image function refuses a guest
-- past 10 an hour per visitor, or once all guests together reach 300 a day.
-- Signed-in users are not counted or limited.
--
-- The visitor is a SHA-256 hash of their IP address, never the address itself.

create table public.guest_triage_uses (
    id         bigint generated always as identity primary key,
    visitor    text        not null,
    created_at timestamptz not null default now()
);
create index guest_triage_uses_visitor_time on public.guest_triage_uses (visitor, created_at);
create index guest_triage_uses_time on public.guest_triage_uses (created_at);

-- Server only: row level security with no policies, so only the service role
-- (the analyze-image function) can read or write it.
alter table public.guest_triage_uses enable row level security;
revoke all on public.guest_triage_uses from anon, authenticated;

-- Counts and records one guest use atomically. Returns 'ok', 'visitor' (this
-- visitor hit the hourly limit) or 'site' (the daily cap for all guests).
create or replace function public.claim_guest_triage(p_visitor text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    c_per_visitor_hour constant integer := 10;
    c_site_per_day     constant integer := 300;
begin
    -- One claim at a time, so two requests can't both slip under a limit.
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
    -- Old rows are only needed for the rolling day.
    delete from public.guest_triage_uses where created_at < now() - interval '2 days';
    return 'ok';
end;
$$;
revoke execute on function public.claim_guest_triage(text) from public, anon, authenticated;
grant execute on function public.claim_guest_triage(text) to service_role;
