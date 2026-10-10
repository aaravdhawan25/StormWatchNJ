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

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT,              -- NULL for Google-only accounts
    role TEXT NOT NULL DEFAULT 'resident',   -- 'resident' or 'township'
    township TEXT,
    verified INTEGER NOT NULL DEFAULT 0,
    failed_logins INTEGER NOT NULL DEFAULT 0,
    locked_until TEXT,
    created_at TEXT NOT NULL
);

-- Only a hash of each session token is kept, so a copy of this database does
-- not hand anyone a working login.
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS email_codes (
    user_id TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    sent_at TEXT NOT NULL
);

-- One "it's gone" vote per account per hazard.
CREATE TABLE IF NOT EXISTS hazard_votes (
    hazard_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (hazard_id, user_id)
);

-- A removed hazard leaves the live table entirely. This keeps the minimum
-- needed to answer "what was removed, when, and why" — three accounts being
-- able to erase a hazard with no trace would be an abuse vector.
CREATE TABLE IF NOT EXISTS removed_hazards (
    id TEXT PRIMARY KEY,
    report_type TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    created_at TEXT NOT NULL,
    removed_at TEXT NOT NULL,
    reason TEXT NOT NULL,            -- 'reporter', 'township', 'community'
    removed_by TEXT
);
"""

NOT_THERE_THRESHOLD = 3


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
        # Databases created before accounts existed lack the owner column.
        columns = {row["name"] for row in conn.execute("PRAGMA table_info(hazard_reports)")}
        if "owner_id" not in columns:
            conn.execute("ALTER TABLE hazard_reports ADD COLUMN owner_id TEXT")


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
                media_url, municipality, address, zipcode, latitude, longitude, created_at, updated_at,
                owner_id)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (report_id, fields["report_type"], fields["severity"], fields["road_status"],
             1 if fields.get("utility_lines_involved") else 0, fields["description"],
             fields.get("media_url"), fields.get("municipality"), fields.get("address"),
             fields.get("zipcode"), fields["latitude"], fields["longitude"], stamp, stamp,
             fields.get("owner_id")),
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


# --- Removal -----------------------------------------------------------------

def remove(report_id, reason, removed_by=None):
    """Deletes a hazard from the live table, leaving an audit row."""
    with connect() as conn:
        row = conn.execute("SELECT * FROM hazard_reports WHERE id = ?", (report_id,)).fetchone()
        if row is None:
            return False
        conn.execute(
            """INSERT OR REPLACE INTO removed_hazards
               (id, report_type, latitude, longitude, created_at, removed_at, reason, removed_by)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (row["id"], row["report_type"], row["latitude"], row["longitude"],
             row["created_at"], now_iso(), reason, removed_by),
        )
        conn.execute("DELETE FROM hazard_votes WHERE hazard_id = ?", (report_id,))
        conn.execute("DELETE FROM hazard_reports WHERE id = ?", (report_id,))
    return True


def add_not_there_vote(report_id, user_id):
    """Records a vote (idempotent per account) and returns the distinct total."""
    with connect() as conn:
        conn.execute(
            "INSERT OR IGNORE INTO hazard_votes (hazard_id, user_id, created_at) VALUES (?, ?, ?)",
            (report_id, user_id, now_iso()),
        )
        row = conn.execute(
            "SELECT COUNT(*) AS n FROM hazard_votes WHERE hazard_id = ?", (report_id,)
        ).fetchone()
    return row["n"]


def vote_summary(user_id=None):
    """{hazard_id: (vote_count, this_user_voted)} for every hazard with votes."""
    with connect() as conn:
        rows = conn.execute("SELECT hazard_id, user_id FROM hazard_votes").fetchall()
    summary = {}
    for row in rows:
        count, mine = summary.get(row["hazard_id"], (0, False))
        summary[row["hazard_id"]] = (count + 1, mine or row["user_id"] == user_id)
    return summary


def set_status(report_id, status):
    with connect() as conn:
        conn.execute("UPDATE hazard_reports SET status = ?, updated_at = ? WHERE id = ?",
                     (status, now_iso(), report_id))
    return get(report_id)
