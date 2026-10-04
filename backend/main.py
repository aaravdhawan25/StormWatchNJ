"""StormWatch NJ API.

  * /api/v1/analyze-image            Gemini hazard triage
  * /georeport/v2/...                Open311 GeoReport v2 (see open311.py)
  * /api/v1/hazards/feed.geojson     live GIS layer for ArcGIS Online / QGIS
  * /api/v1/integrations/...         municipal dispatch relay (see integrations.py)

The iOS app works without this service (it falls back to on-device analysis and
keeps reports locally). Run it for Gemini triage and the municipal hand-offs:

    pip install -r requirements.txt
    export GOOGLE_API_KEY=...
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Then, in the app's DPW tab, turn on "Use backend for AI triage" and point it at
http://127.0.0.1:8000 (simulator) or http://<your-mac-ip>:8000 (device).
"""

import os
from enum import Enum

from contextlib import asynccontextmanager

from fastapi import BackgroundTasks, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import integrations
import open311
import storage


@asynccontextmanager
async def lifespan(_app):
    storage.init()
    yield


app = FastAPI(title="StormWatch NJ API", version="1.1.0", lifespan=lifespan)
app.include_router(open311.router)

# The mobile client is not a browser, but CORS keeps the DPW web export usable
# from a local dashboard during development.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MODEL = os.environ.get("GEMINI_MODEL", "gemini-1.5-flash")


class HazardType(str, Enum):
    CLOGGED_DRAIN = "CLOGGED_DRAIN"
    STREET_FLOODING = "STREET_FLOODING"
    DOWNED_TREE = "DOWNED_TREE"
    DOWNED_WIRE = "DOWNED_WIRE"
    OTHER = "OTHER"


class SeverityLevel(str, Enum):
    LOW = "LOW"
    MODERATE = "MODERATE"
    IMPASSABLE = "IMPASSABLE"


class RoadStatus(str, Enum):
    CLEAR_TO_PASS = "CLEAR_TO_PASS"
    ONE_LANE_OPEN = "ONE_LANE_OPEN"
    IMPASSABLE = "IMPASSABLE"


class HazardAnalysisResult(BaseModel):
    hazard_type: HazardType
    severity: SeverityLevel
    utility_lines_involved: bool = Field(
        description="True if electrical or utility lines appear snapped, tangled, or touching water/trees."
    )
    road_status: RoadStatus = Field(
        description="Whether a vehicle can still get through."
    )
    suggested_description: str = Field(
        description="Concise 1-2 sentence factual report for emergency DPW crew dispatch."
    )


SYSTEM_PROMPT = """You are StormWatch NJ's automated civic infrastructure triage assistant.
Inspect the uploaded storm incident photo.
1. Determine the primary hazard category.
2. Determine travel impassability and severity.
3. Crucial Safety Check: Look carefully for utility or electrical wires caught in fallen trees or water.
4. Output a clean, objective description. Describe only what is visible; do not speculate.
"""


def get_client():
    """Builds the GenAI client lazily so the service still starts without a key."""
    if not os.environ.get("GOOGLE_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="GOOGLE_API_KEY is not set. The iOS app will fall back to on-device triage.",
        )
    from google import genai

    return genai.Client()


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": MODEL,
        "gemini_configured": bool(os.environ.get("GOOGLE_API_KEY")),
        "api_keys_required": bool(open311.configured_keys()),
        "dispatch_towns_configured": len(integrations.load_config().get("towns", {})),
    }


@app.get("/api/v1/hazards/feed.geojson")
def hazard_feed(status: str = "open"):
    """Open GIS layer of hazards, RFC 7946.

    Paste this URL into ArcGIS Online ("Add layer from URL" → GeoJSON) or QGIS
    ("Add Vector Layer" → Protocol) to get a live storm layer. `?status=all`
    includes resolved reports.
    """
    reports = storage.query(status=None if status == "all" else "open")
    features = [
        {
            "type": "Feature",
            "id": r["id"],
            # GeoJSON is longitude-first.
            "geometry": {"type": "Point", "coordinates": [r["longitude"], r["latitude"]]},
            "properties": {
                "report_type": r["report_type"],
                "severity": r["severity"],
                "road_status": r["road_status"],
                "utility_lines_involved": bool(r["utility_lines_involved"]),
                "description": r["description"],
                "address": r["address"],
                "municipality": r["municipality"],
                "zipcode": r["zipcode"],
                "status": r["status"],
                "confirmations": r["upvotes"],
                "created_at": r["created_at"],
                "updated_at": r["updated_at"],
                "map_url": integrations.maps_link(r),
            },
        }
        for r in reports
    ]
    return JSONResponse(
        content={"type": "FeatureCollection", "source": "StormWatch NJ", "generated_at": storage.now_iso(),
                 "features": features},
        media_type="application/geo+json",
    )


class DispatchRequest(BaseModel):
    service_request_id: str
    api_key: str = ""


@app.post("/api/v1/integrations/dispatch-alert")
async def dispatch_incident(body: DispatchRequest, background_tasks: BackgroundTasks):
    """Re-send a stored report to its town's public works desk.

    Takes the id of a report already on file rather than an arbitrary payload:
    an endpoint that forwards whatever JSON it is handed to a government inbox
    is an open relay.
    """
    if not open311.key_is_valid(body.api_key):
        raise HTTPException(status_code=403, detail="Missing or invalid api_key.")
    if storage.get(body.service_request_id) is None:
        raise HTTPException(status_code=404, detail="No report with that id.")
    # Runs in the background so a slow town endpoint never stalls the client.
    background_tasks.add_task(integrations.forward_to_agency_dispatch, body.service_request_id)
    return {"status": "DISPATCH_QUEUED"}


@app.post("/api/v1/analyze-image", response_model=HazardAnalysisResult)
async def analyze_hazard_image(file: UploadFile = File(...)):
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image.")

    image_bytes = await file.read()
    client = get_client()

    from google.genai import types

    try:
        response = client.models.generate_content(
            model=MODEL,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=file.content_type),
                SYSTEM_PROMPT,
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=HazardAnalysisResult,
                temperature=0.1,
            ),
        )
        return HazardAnalysisResult.model_validate_json(response.text)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"AI Vision processing failed: {exc}") from exc
