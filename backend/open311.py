"""Open311 GeoReport v2 endpoint.

Implements the civic standard at https://wiki.open311.org/GeoReport_v2/ so a
town whose ticketing system already speaks Open311 can federate with StormWatch
NJ without custom work. The iOS app files its own reports through this same
endpoint.

Where this implementation is narrower than the spec:
  * JSON only (the spec also allows XML).
  * `lat` and `long` are required. The spec lets a client send `address_string`
    alone, but there is no geocoder here to place it on the map.
  * `email`, `first_name`, `last_name` and `phone` are accepted and discarded —
    see storage.py.
"""

import os
import re
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Request
from fastapi.responses import JSONResponse

import integrations
import storage

router = APIRouter(prefix="/georeport/v2", tags=["Open311 GeoReport v2"])

AGENCY = "StormWatch NJ Civic Network"

SERVICES = {
    "CLOGGED_DRAIN": ("Clogged Storm Drain", "Catch basin or storm drain blocked, water ponding at the curb.", "Stormwater"),
    "STREET_FLOODING": ("Street Flooding", "Standing or moving water across a roadway.", "Stormwater"),
    "DOWNED_TREE": ("Downed Tree", "Tree or large limb obstructing a road or sidewalk.", "Roads"),
    "DOWNED_WIRE": ("Downed Wire", "Utility line down. Callers should also dial 911 and the utility.", "Utilities"),
    "OTHER": ("Other Storm Hazard", "Storm-related obstruction not covered above.", "Roads"),
}

SEVERITIES = ["LOW", "MODERATE", "IMPASSABLE"]
ROAD_STATUSES = ["CLEAR_TO_PASS", "ONE_LANE_OPEN", "IMPASSABLE"]

ATTRIBUTES = [
    {"variable": True, "code": "severity", "datatype": "singlevaluelist", "required": False,
     "datatype_description": None, "order": 1, "description": "How bad is it?",
     "values": [{"key": s, "name": s.title()} for s in SEVERITIES]},
    {"variable": True, "code": "road_status", "datatype": "singlevaluelist", "required": False,
     "datatype_description": None, "order": 2, "description": "Can traffic get through?",
     "values": [{"key": s, "name": s.replace("_", " ").title()} for s in ROAD_STATUSES]},
    {"variable": True, "code": "utility_lines_involved", "datatype": "singlevaluelist", "required": False,
     "datatype_description": None, "order": 3, "description": "Are utility lines down or tangled in it?",
     "values": [{"key": "true", "name": "Yes"}, {"key": "false", "name": "No"}]},
    {"variable": True, "code": "municipality", "datatype": "string", "required": False,
     "datatype_description": "Town name", "order": 4, "description": "Municipality", "values": []},
    {"variable": True, "code": "zipcode", "datatype": "string", "required": False,
     "datatype_description": "5-digit ZIP", "order": 5,
     "description": "ZIP code, used to route the report to the right public works desk.", "values": []},
]

NJ_ZIP = re.compile(r"\b0[78]\d{3}\b")


def error(status, description):
    """Open311's error shape: a list of {code, description}."""
    return JSONResponse(status_code=status, content=[{"code": status, "description": description}])


def configured_keys():
    return {k.strip() for k in os.environ.get("STORMWATCH_API_KEYS", "").split(",") if k.strip()}


def key_is_valid(api_key):
    """With no keys configured the API runs in open development mode."""
    keys = configured_keys()
    return not keys or api_key in keys


def to_open311(report):
    name = SERVICES.get(report["report_type"], SERVICES["OTHER"])[0]
    return {
        "service_request_id": report["id"],
        "status": "closed" if report["status"] == "RESOLVED" else "open",
        "status_notes": {"ACTIVE": "Reported", "IN_PROGRESS": "Crew assigned", "RESOLVED": "Resolved"}.get(report["status"]),
        "service_name": name,
        "service_code": report["report_type"],
        "description": report["description"],
        "agency_responsible": AGENCY,
        "service_notice": "Unverified resident report, triaged by software.",
        "requested_datetime": report["created_at"],
        "updated_datetime": report["updated_at"],
        "expected_datetime": None,
        "address": report["address"],
        "address_id": None,
        "zipcode": report["zipcode"],
        "lat": report["latitude"],
        "long": report["longitude"],
        "media_url": report["media_url"],
    }


def parse_date(value):
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds")


@router.get("/discovery.json")
def discovery(request: Request):
    base = str(request.base_url).rstrip("/") + "/georeport/v2"
    return {
        "changeset": "2026-10-03T00:00:00+00:00",
        "contact": "See the project README.",
        "key_service": "Set STORMWATCH_API_KEYS on the server; unset means open development mode.",
        "endpoints": [{
            "specification": "http://wiki.open311.org/GeoReport_v2",
            "url": base,
            "changeset": "2026-10-03T00:00:00+00:00",
            "type": "production" if configured_keys() else "test",
            "formats": ["application/json"],
        }],
    }


@router.get("/services.json")
def service_list():
    return [
        {"service_code": code, "service_name": name, "description": description,
         "metadata": True, "type": "realtime", "keywords": code.lower().replace("_", ","), "group": group}
        for code, (name, description, group) in SERVICES.items()
    ]


@router.get("/services/{service_code}.json")
def service_definition(service_code: str):
    if service_code not in SERVICES:
        return error(404, f"service_code '{service_code}' was not found.")
    return {"service_code": service_code, "attributes": ATTRIBUTES}


@router.post("/requests.json", status_code=201)
async def create_request(request: Request, background_tasks: BackgroundTasks):
    form = await request.form()

    if not key_is_valid(form.get("api_key", "")):
        return error(403, "Missing or invalid api_key.")

    service_code = form.get("service_code")
    if not service_code:
        return error(400, "service_code is required.")
    if service_code not in SERVICES:
        return error(404, f"service_code '{service_code}' was not found.")

    try:
        lat, lon = float(form["lat"]), float(form["long"])
    except (KeyError, ValueError):
        return error(400, "lat and long are required and must be numbers. address_string alone cannot be placed on the map.")
    if not storage.in_service_area(lat, lon):
        return error(400, "Location is outside New Jersey, the service area for this endpoint.")

    severity = form.get("attribute[severity]", "MODERATE")
    road_status = form.get("attribute[road_status]", "ONE_LANE_OPEN")
    if severity not in SEVERITIES:
        return error(400, f"attribute[severity] must be one of {', '.join(SEVERITIES)}.")
    if road_status not in ROAD_STATUSES:
        return error(400, f"attribute[road_status] must be one of {', '.join(ROAD_STATUSES)}.")

    description = (form.get("description") or SERVICES[service_code][0]).strip()
    if len(description) > 4000:
        return error(400, "description must be 4000 characters or fewer.")

    address = (form.get("address_string") or "").strip() or None
    zipcode = (form.get("attribute[zipcode]") or "").strip()
    if not zipcode and address:
        found = NJ_ZIP.search(address)
        zipcode = found.group(0) if found else ""

    # A second neighbor reporting the same hazard confirms it rather than
    # opening — and dispatching — a second ticket.
    duplicate = storage.find_duplicate(service_code, lat, lon)
    if duplicate:
        storage.add_upvote(duplicate["id"])
        return [{
            "service_request_id": duplicate["id"],
            "service_notice": "Matched an open report nearby; recorded as a confirmation.",
            "account_id": None,
        }]

    utility = form.get("attribute[utility_lines_involved]", "").lower() == "true" or service_code == "DOWNED_WIRE"
    report = storage.create({
        "report_type": service_code,
        "severity": severity,
        "road_status": road_status,
        "utility_lines_involved": utility,
        "description": description,
        "media_url": form.get("media_url") or None,
        "municipality": (form.get("attribute[municipality]") or "").strip() or None,
        "address": address,
        "zipcode": zipcode or None,
        "latitude": lat,
        "longitude": lon,
    })

    background_tasks.add_task(integrations.forward_to_agency_dispatch, report["id"])
    return [{
        "service_request_id": report["id"],
        "service_notice": "Received. Forwarded to public works where the town has opted in.",
        "account_id": None,
    }]


@router.get("/requests.json")
def list_requests(service_request_id: str = "", service_code: str = "", status: str = "",
                  start_date: str = "", end_date: str = ""):
    if status and status not in ("open", "closed"):
        return error(400, "status must be 'open' or 'closed'.")
    start, end = parse_date(start_date) if start_date else None, parse_date(end_date) if end_date else None
    if (start_date and not start) or (end_date and not end):
        return error(400, "start_date and end_date must be ISO 8601 datetimes.")
    reports = storage.query(
        ids=[i for i in service_request_id.split(",") if i] or None,
        report_types=[c for c in service_code.split(",") if c] or None,
        status=status or None, start=start, end=end,
    )
    return [to_open311(r) for r in reports]


@router.get("/requests/{request_id}.json")
def get_request(request_id: str):
    report = storage.get(request_id)
    if report is None:
        return error(404, f"service_request_id '{request_id}' was not found.")
    return [to_open311(report)]
