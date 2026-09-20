"""Polls USGS river gauges for New Jersey on a 15-minute schedule.

The iOS app calls the USGS API directly, so this worker is only needed when you
want the readings persisted in PostgreSQL for the DPW dashboard.

    python usgs_worker.py
"""

import os

import requests

# Parameter 00065 is gage height in feet. The site list matches
# StormWatchNJ/Services/NJStationCatalog.swift in the iOS app.
SITES = [
    "01402000", "01400500", "01403060", "01396500", "01379000",
    "01389500", "01391500", "01381500", "01445500", "01408000",
    "01467000",
]

USGS_URL = "https://waterservices.usgs.gov/nwis/iv/"


def fetch_readings():
    response = requests.get(
        USGS_URL,
        params={
            "format": "json",
            "sites": ",".join(SITES),
            "parameterCd": "00065",
            "siteStatus": "active",
        },
        timeout=15,
    )
    response.raise_for_status()
    series = response.json()["value"]["timeSeries"]

    readings = {}
    for entry in series:
        site_code = entry["sourceInfo"]["siteCode"][0]["value"]
        site_name = entry["sourceInfo"]["siteName"]
        values = entry["values"][0]["value"]
        if not values:
            continue
        height = float(values[-1]["value"])
        # USGS uses -999999 as its "no data" sentinel.
        if height < -900000:
            continue
        readings[site_code] = (site_name, height, values[-1]["dateTime"])
    return readings


def persist(readings):
    """Writes readings into the usgs_stations table, if DATABASE_URL is set."""
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        print("DATABASE_URL not set — printing only.")
        return

    import psycopg2

    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        for site_code, (_, height, observed_at) in readings.items():
            cur.execute(
                """
                UPDATE usgs_stations
                   SET current_gauge_height_ft = %s,
                       alert_status = CASE
                           WHEN %s >= flood_stage_ft + 3 THEN 'MAJOR'
                           WHEN %s >= flood_stage_ft     THEN 'FLOOD'
                           WHEN %s >= flood_stage_ft - 2 THEN 'ACTION'
                           ELSE 'NORMAL'
                       END,
                       last_updated = %s
                 WHERE site_id = %s
                """,
                (height, height, height, height, observed_at, site_code),
            )
        conn.commit()
    print(f"Persisted {len(readings)} readings.")


def poll_usgs_sensors():
    readings = fetch_readings()
    print(f"Polled {len(readings)} USGS stations across New Jersey.")
    for site_code, (site_name, height, observed_at) in sorted(readings.items()):
        print(f"  {site_code} {site_name}: {height} ft at {observed_at}")
    persist(readings)


if __name__ == "__main__":
    poll_usgs_sensors()
