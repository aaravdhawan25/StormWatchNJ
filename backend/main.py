"""StormWatch NJ API — multimodal hazard triage.

The iOS app works without this service (it falls back to on-device Vision
classification). Run it when you want Gemini-quality triage:

    pip install -r requirements.txt
    export GOOGLE_API_KEY=...
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Then, in the app's DPW tab, turn on "Use backend for AI triage" and point it at
http://127.0.0.1:8000 (simulator) or http://<your-mac-ip>:8000 (device).
"""

import os
from enum import Enum

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI(title="StormWatch NJ API", version="1.0.0")

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
    return {"status": "ok", "model": MODEL, "gemini_configured": bool(os.environ.get("GOOGLE_API_KEY"))}


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
