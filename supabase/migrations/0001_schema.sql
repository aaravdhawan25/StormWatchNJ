-- StormWatch NJ — tables.
--
-- Every table has row level security on and NO policies for app users. Nothing
-- is read or written directly: the app goes through the functions in
-- 0002_rules.sql, which decide who may do what. That keeps `owner_id` — who
-- reported a hazard — from ever reaching another user.

create extension if not exists postgis with schema extensions;

-- Municipal email domains that may hold a township account. Supplied by the
-- project owner and not independently verified town by town; review before
-- real use.
create table public.township_domains (
    domain text primary key check (domain = lower(domain)),
    name   text not null,
    county text not null
);

insert into public.township_domains (domain, name, county) values
    ('ewingnj.org',        'Ewing Township',          'Mercer'),
    ('hopewellboro-nj.us', 'Hopewell Borough',        'Mercer'),
    ('hopewelltwp.org',    'Hopewell Township',       'Mercer'),
    ('penningtonboro.org', 'Pennington Borough',      'Mercer'),
    ('princetonnj.gov',    'Princeton',               'Mercer'),
    ('trentonnj.org',      'Trenton',                 'Mercer'),
    ('westwindsortwp.com', 'West Windsor Township',   'Mercer'),
    ('cranbury-nj.com',    'Cranbury Township',       'Middlesex'),
    ('dunellen-nj.gov',    'Dunellen Borough',        'Middlesex'),
    ('eastbrunswick.org',  'East Brunswick Township', 'Middlesex'),
    ('oldbridge.com',      'Old Bridge Township',     'Middlesex'),
    ('plainsboronj.com',   'Plainsboro Township',     'Middlesex'),
    ('sbtnj.net',          'South Brunswick Township','Middlesex'),
    ('southrivernj.org',   'South River Borough',     'Middlesex'),
    ('spotswoodboro.com',  'Spotswood Borough',       'Middlesex'),
    ('boundbrook-nj.org',  'Bound Brook Borough',     'Somerset'),
    ('bridgewaternj.gov',  'Bridgewater Township',    'Somerset'),
    ('franklintwpnj.org',  'Franklin Township',       'Somerset'),
    ('plainfieldnj.gov',   'Plainfield',              'Union');

-- One row per account, maintained by a trigger on auth.users. `role` is never
-- written by a client.
create table public.profiles (
    id         uuid primary key references auth.users (id) on delete cascade,
    role       text not null default 'resident' check (role in ('resident', 'township')),
    township   text,
    updated_at timestamptz not null default now()
);

create table public.hazards (
    id          uuid primary key default gen_random_uuid(),
    report_type text not null check (report_type in
                    ('CLOGGED_DRAIN', 'STREET_FLOODING', 'DOWNED_TREE', 'DOWNED_WIRE', 'OTHER')),
    severity    text not null check (severity in ('LOW', 'MODERATE', 'IMPASSABLE')),
    road_status text not null check (road_status in ('CLEAR_TO_PASS', 'ONE_LANE_OPEN', 'IMPASSABLE')),
    utility_lines_involved boolean not null default false,
    description text not null check (char_length(description) between 1 and 4000),
    municipality text,
    address     text,
    zipcode     text,
    -- New Jersey's bounding box: the service area.
    latitude    double precision not null check (latitude between 38.86 and 41.40),
    longitude   double precision not null check (longitude between -75.61 and -73.88),
    location    extensions.geography(Point, 4326) generated always as (
                    extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326)::extensions.geography
                ) stored,
    status      text not null default 'ACTIVE' check (status in ('ACTIVE', 'IN_PROGRESS', 'RESOLVED')),
    upvotes     integer not null default 1,
    owner_id    uuid references auth.users (id) on delete set null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    dispatched_at timestamptz
);

create index hazards_location_idx on public.hazards using gist (location);
create index hazards_status_idx   on public.hazards (status);
create index hazards_owner_idx    on public.hazards (owner_id);

-- One "it's gone" vote per account per hazard.
create table public.hazard_votes (
    hazard_id  uuid not null references public.hazards (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (hazard_id, user_id)
);
create index hazard_votes_user_idx on public.hazard_votes (user_id);

-- A removed hazard leaves `hazards` entirely. This keeps the minimum needed to
-- answer "what was removed, when, and why": three accounts being able to erase
-- a hazard without trace would invite abuse.
create table public.removed_hazards (
    id          uuid primary key,
    report_type text not null,
    latitude    double precision not null,
    longitude   double precision not null,
    created_at  timestamptz not null,
    removed_at  timestamptz not null default now(),
    reason      text not null check (reason in ('reporter', 'township', 'community')),
    removed_by  uuid
);

-- Where reports are forwarded, by ZIP. Empty until a town opts in — there are
-- deliberately no built-in destinations.
create table public.dispatch_towns (
    zipcode     text primary key,
    name        text not null,
    webhook_url text,
    email       text,
    enabled     boolean not null default true
);

alter table public.township_domains enable row level security;
alter table public.profiles         enable row level security;
alter table public.hazards          enable row level security;
alter table public.hazard_votes     enable row level security;
alter table public.removed_hazards  enable row level security;
alter table public.dispatch_towns   enable row level security;

-- The list of recognised towns is public information and is shown on the
-- sign-in screen before anyone has an account.
create policy "township domains are public" on public.township_domains
    for select to anon, authenticated using (true);

-- A signed-in user may read their own profile, nothing else.
create policy "read own profile" on public.profiles
    for select to authenticated using ((select auth.uid()) = id);
