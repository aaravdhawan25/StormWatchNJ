"""SQLite persistence for hazard reports.

The production target is PostgreSQL + PostGIS (see schema.sql). SQLite is used
here so the API runs with zero setup — no server, no extension — which matters
for a demo and for tests. The table mirrors `hazard_reports` in schema.sql, with
plain latitude/longitude columns standing in for the PostGIS geometry.

No reporter contact details are stored. Open311 lets a client send a name, email
and phone; this service deliberately drops them, so the open GeoJSON feed can
never leak who filed a report.
"""

import math
import os
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone

DB_PATH = os.environ.get("STORMWATCH_DB", os.path.join(os.path.dirname(__file__), "stormwatch.db"))

# New Jersey's bounding box — the same service area the iOS app enforces.
NJ_BOUNDS = {"min_lat": 38.86, "max_lat": 41.40, "min_lon": -75.61, "max_lon": -73.88}

SCHEMA = """
CREATE TABLE IF NOT EXISTS hazard_reports (
    id TEXT PRIMARY KEY,
    report_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    road_status TEXT NOT NULL,
    utility_lines_involved INTEGER NOT NULL DEFAULT 0,
    description TEXT NOT NULL,
    media_url TEXT,
    municipality TEXT,
    address TEXT,
    zipcode TEXT,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    upvotes INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    dispatched_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_hazard_status ON hazard_reports(status);
CREATE INDEX IF NOT EXISTS idx_hazard_created ON hazard_reports(created_at);
"""


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@contextmanager
def connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init():
    with connect() as conn:
        conn.executescript(SCHEMA)


def in_service_area(lat, lon):
    return (NJ_BOUNDS["min_lat"] <= lat <= NJ_BOUNDS["max_lat"]
            and NJ_BOUNDS["min_lon"] <= lon <= NJ_BOUNDS["max_lon"])


def distance_meters(lat1, lon1, lat2, lon2):
    """Great-circle distance; the SQLite stand-in for PostGIS ST_Distance."""
    radius = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


def find_duplicate(report_type, lat, lon, within_meters=75, within_hours=6):
    """An open report of the same type, close by and recent.

    Several neighbors photographing the same fallen tree should become one
    ticket with several confirmations, not several tickets on a DPW desk.
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=within_hours)).isoformat(timespec="seconds")
    with connect() as conn:
        rows = conn.execute(
            "SELECT * FROM hazard_reports WHERE report_type = ? AND status != 'RESOLVED' AND created_at >= ?",
            (report_type, cutoff),
        ).fetchall()
    for row in rows:
        if distance_meters(lat, lon, row["latitude"], row["longitude"]) <= within_meters:
            return dict(row)
    return None


def add_upvote(report_id):
    with connect() as conn:
        conn.execute(
            "UPDATE hazard_reports SET upvotes = upvotes + 1, updated_at = ? WHERE id = ?",
            (now_iso(), report_id),
        )
    return get(report_id)


def create(fields):
    report_id = str(uuid.uuid4())
    stamp = now_iso()
    with connect() as conn:
        conn.execute(
            """INSERT INTO hazard_reports
               (id, report_type, severity, road_status, utility_lines_involved, description,
                media_url, municipality, address, zipcode, latitude, longitude, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (report_id, fields["report_type"], fields["severity"], fields["road_status"],
             1 if fields.get("utility_lines_involved") else 0, fields["description"],
             fields.get("media_url"), fields.get("municipality"), fields.get("address"),
             fields.get("zipcode"), fields["latitude"], fields["longitude"], stamp, stamp),
        )
    return get(report_id)


def get(report_id):
    with connect() as conn:
        row = conn.execute("SELECT * FROM hazard_reports WHERE id = ?", (report_id,)).fetchone()
    return dict(row) if row else None


def query(ids=None, report_types=None, status=None, start=None, end=None, limit=1000):
    clauses, params = [], []
    if ids:
        clauses.append("id IN (%s)" % ",".join("?" * len(ids)))
        params += ids
    if report_types:
        clauses.append("report_type IN (%s)" % ",".join("?" * len(report_types)))
        params += report_types
    if status == "open":
        clauses.append("status != 'RESOLVED'")
    elif status == "closed":
        clauses.append("status = 'RESOLVED'")
    if start:
        clauses.append("created_at >= ?")
        params.append(start)
    if end:
        clauses.append("created_at <= ?")
        params.append(end)
    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    with connect() as conn:
        rows = conn.execute(
            f"SELECT * FROM hazard_reports {where} ORDER BY created_at DESC LIMIT ?", (*params, limit)
        ).fetchall()
    return [dict(r) for r in rows]


def mark_dispatched(report_id):
    with connect() as conn:
        conn.execute("UPDATE hazard_reports SET dispatched_at = ? WHERE id = ?", (now_iso(), report_id))


def dispatches_in_last_hour(zipcode):
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat(timespec="seconds")
    with connect() as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS n FROM hazard_reports WHERE zipcode = ? AND dispatched_at >= ?",
            (zipcode, cutoff),
        ).fetchone()
    return row["n"]
