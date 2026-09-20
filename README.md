# StormWatch NJ

Hyper-local flash-flood and road-obstruction reporting for New Jersey commuters and
municipal DPW crews. Built for the Congressional App Challenge.

Residents photograph a hazard, an AI triages the photo and pre-fills the report, the
resident confirms it in one tap, and the result lands on a live map alongside real
USGS river-gauge telemetry. Town DPWs export the open queue as GeoJSON or CSV.

## Run it

```bash
open StormWatchNJ.xcodeproj
```

Pick any iPhone simulator and press **⌘R**. Nothing else to install — no package
manager, no API key, no backend. The app ships with seeded demo reports and pulls
live river data on launch.

Requirements: **Xcode 15 or newer**, iOS 17 deployment target.

> Signing: the target uses automatic signing with bundle ID
> `com.stormwatchnj.StormWatchNJ`. The simulator needs no team. To run on a physical
> iPhone, select the target → Signing & Capabilities → pick your Apple ID team and
> change the bundle ID to something unique to you.

## What's in the app

| Tab | What it does |
| --- | --- |
| **Map** | Hazard pins colored by severity plus river-gauge pins, filtered to your search radius. Live counts of impassable roads, downed wires and rising rivers. |
| **Nearby** | Active hazards within the radius, nearest first, filterable by hazard type. |
| **Report** | Snap & Triage: photo → AI analysis → pre-filled draft → you confirm → posted. |
| **Rivers** | All 11 monitored gauges with live gage height against flood stage. Pull to refresh. |
| **DPW** | Open dispatch queue sorted by severity, GeoJSON/CSV export, demo and backend controls. |

### AI triage

By default photos are classified **on-device** with Apple's Vision framework
(`VNClassifyImageRequest`) — no network, no key, works in the simulator. The engine
scores scene labels against four hazard vocabularies, then derives severity, road
status and the blueprint's utility-wire safety check.

Every machine-filled field stays editable and nothing is published until you tap
**Post report**. That human-in-the-loop step is the point, not a limitation.

Flip **Use backend for AI triage** in the DPW tab to route photos to the FastAPI +
Gemini endpoint in `backend/` instead. If that call fails, the app falls back to
on-device triage and tells you why.

### River telemetry

The app polls the [USGS Water Services](https://waterservices.usgs.gov/) instantaneous-values
API for gage height (parameter `00065`) at 11 NJ sites across the Raritan, Millstone,
Passaic, Saddle, Manasquan, Pequest and Rancocas basins. The API is public and needs
no key, so the client calls it directly.

**Flood-stage thresholds in this build are demo values**, not official numbers. Replace
them with the NWS AHPS stages for each site before this is used for anything real.
Station names and coordinates are the live values USGS returns.

### Simulate Nor'easter

DPW tab → **Simulate nor'easter**. Adds clearly-labelled simulated hazards and pushes
every gauge past flood stage, so the map, alert banner and export all have something
to show on a clear day — useful when recording the two-minute submission video. Turn
it off to return to live data.

All seeded and simulated reports are fictional sample data, not records of real incidents.

## Optional backend

The app is fully functional without it. Run it for Gemini triage or to persist
readings in PostGIS:

```bash
cd backend
pip install -r requirements.txt
export GOOGLE_API_KEY=your-key
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Then set the backend URL in the DPW tab to `http://127.0.0.1:8000` (simulator) or
`http://<your-mac-ip>:8000` (physical device).

- `main.py` — `/api/v1/analyze-image`, Gemini with a strict JSON response schema
- `usgs_worker.py` — 15-minute polling worker, prints or persists to PostgreSQL
- `schema.sql` — PostGIS tables, indexes, station seed, and the `ST_DWithin` query
- `.env.example` — configuration template

`HazardStore.nearby(_:radiusMiles:)` in the app is the client-side equivalent of the
`ST_DWithin` five-mile query in `schema.sql`.

## Project layout

```
StormWatch/
├── StormWatchNJ.xcodeproj/
├── StormWatchNJ/
│   ├── StormWatchNJApp.swift
│   ├── Info.plist
│   ├── Models/          HazardReport, USGSStation and their enums
│   ├── Services/        Store, USGS polling, triage engines, location, export
│   └── Views/           Map, list, snap & triage, rivers, DPW console
├── Tools/
│   └── generate_xcodeproj.py
└── backend/
```

### Regenerating the project file

`project.pbxproj` is generated, not hand-edited. After adding or deleting a Swift file
in `Models/`, `Services/` or `Views/`, run:

```bash
python3 Tools/generate_xcodeproj.py
```

Adding files through Xcode's UI works too — the generator just keeps the file tidy and
diffable, and lets the project be rebuilt from scratch.

## Privacy

Photos stay on the device; only the fields you confirm are published. Your location is
attached to a report only when you submit one, and is never uploaded on its own.
