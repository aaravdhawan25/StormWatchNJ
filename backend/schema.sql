-- StormWatch NJ — PostgreSQL + PostGIS schema.
-- Run against a fresh database (Supabase, Neon, or local Postgres).

-- 1. Geospatial capabilities
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Hazard reports (crowdsourced + AI triaged)
CREATE TABLE IF NOT EXISTS hazard_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_type VARCHAR(32) NOT NULL,             -- 'CLOGGED_DRAIN', 'STREET_FLOODING', 'DOWNED_TREE', 'DOWNED_WIRE', 'OTHER'
    severity VARCHAR(16) NOT NULL,                -- 'LOW', 'MODERATE', 'IMPASSABLE'
    road_status VARCHAR(24) DEFAULT 'ONE_LANE_OPEN', -- 'CLEAR_TO_PASS', 'ONE_LANE_OPEN', 'IMPASSABLE'
    utility_lines_involved BOOLEAN DEFAULT FALSE,
    description TEXT NOT NULL,
    photo_url TEXT,
    municipality VARCHAR(64),
    location GEOMETRY(Point, 4326) NOT NULL,      -- WGS 84 (longitude, latitude)
    status VARCHAR(20) DEFAULT 'ACTIVE',          -- 'ACTIVE', 'IN_PROGRESS', 'RESOLVED'
    upvotes INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hazard_location ON hazard_reports USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_hazard_status ON hazard_reports(status);

-- 3. USGS river gauge stations
CREATE TABLE IF NOT EXISTS usgs_stations (
    site_id VARCHAR(16) PRIMARY KEY,              -- e.g. '01400500' (Millstone River at Blackwells Mills)
    station_name VARCHAR(128) NOT NULL,
    county VARCHAR(64) NOT NULL,
    location GEOMETRY(Point, 4326) NOT NULL,
    flood_stage_ft NUMERIC(5, 2) NOT NULL,
    current_gauge_height_ft NUMERIC(5, 2),
    alert_status VARCHAR(16) DEFAULT 'NORMAL',    -- 'NORMAL', 'ACTION', 'FLOOD', 'MAJOR'
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_station_location ON usgs_stations USING GIST (location);

-- 4. Seed the stations the iOS app watches.
-- Flood stages here are DEMO thresholds; replace them with official NWS AHPS
-- values for each site before any real deployment.
INSERT INTO usgs_stations (site_id, station_name, county, location, flood_stage_ft) VALUES
    ('01402000', 'Millstone River at Blackwells Mills', 'Somerset', ST_SetSRID(ST_MakePoint(-74.5758, 40.4750), 4326),  7.00),
    ('01400500', 'Raritan River at Manville', 'Somerset', ST_SetSRID(ST_MakePoint(-74.5828, 40.5556), 4326), 10.00),
    ('01403060', 'Raritan River below Calco Dam at Bound Brook', 'Somerset', ST_SetSRID(ST_MakePoint(-74.5483, 40.5511), 4326), 28.00),
    ('01396500', 'South Branch Raritan River near High Bridge', 'Hunterdon', ST_SetSRID(ST_MakePoint(-74.8792, 40.6778), 4326),  8.50),
    ('01379000', 'Passaic River near Millington', 'Morris', ST_SetSRID(ST_MakePoint(-74.5289, 40.6800), 4326),  8.00),
    ('01389500', 'Passaic River at Little Falls', 'Passaic', ST_SetSRID(ST_MakePoint(-74.2261, 40.8847), 4326),  7.00),
    ('01391500', 'Saddle River at Lodi', 'Bergen', ST_SetSRID(ST_MakePoint(-74.0806, 40.8903), 4326),  6.00),
    ('01381500', 'Whippany River at Morristown', 'Morris', ST_SetSRID(ST_MakePoint(-74.4569, 40.8072), 4326),  5.00),
    ('01445500', 'Pequest River at Pequest', 'Warren', ST_SetSRID(ST_MakePoint(-74.9778, 40.8306), 4326),  5.00),
    ('01408000', 'Manasquan River at Squankum', 'Monmouth', ST_SetSRID(ST_MakePoint(-74.1547, 40.1614), 4326),  6.00),
    ('01467000', 'North Branch Rancocas Creek at Pemberton', 'Burlington', ST_SetSRID(ST_MakePoint(-74.6844, 39.9700), 4326),  4.50)
ON CONFLICT (site_id) DO NOTHING;

-- 5. Core spatial query: active hazards within 5 miles (8,046 m) of a commuter.
--    This is what HazardStore.nearby(_:radiusMiles:) reimplements client-side.
--
-- SELECT id, report_type, severity, road_status, utility_lines_involved, description, photo_url,
--        ST_Distance(location::geography, ST_MakePoint(:user_lon, :user_lat)::geography) AS distance_meters
--   FROM hazard_reports
--  WHERE status = 'ACTIVE'
--    AND ST_DWithin(location::geography, ST_MakePoint(:user_lon, :user_lat)::geography, 8046)
--  ORDER BY distance_meters ASC;
