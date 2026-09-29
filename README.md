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
| **Report** | Snap & Triage: photo → AI analysis → pre-filled draft → you confirm → posted. Camera, photo library, or two built-in sample scenes. |
| **Rivers** | All 11 monitored gauges with live gage height against flood stage. Pull to refresh. |
| **DPW** | Open dispatch queue sorted by severity, GeoJSON/CSV export, demo and backend controls. |

### AI triage

Photos are analyzed **on-device** by default — no network, no key. Two independent
lines of evidence are combined:

1. **Apple's Vision scene classifier** (`VNClassifyImageRequest`), matched against
   *exact* identifiers from its 1,303-label taxonomy. Substring matching is actively
   wrong here: `"tree"` matches `street`, `"line"` matches `feline`, `"car"` matches
   `carrot`.
2. **Colour analysis** (`ImageSignals`), because that taxonomy has no label for
   flooding, a blocked drain or a downed wire. Blue-tinted and silty-brown pixels
   count fully toward "water"; flat neutral grey counts only partially, since dry
   asphalt is grey too. On the bundled sample scenes a flooded road measures 0.85
   water coverage against 0.14 for a dry road — that separation is what the hazard
   scoring rests on.

The engine shows its working: every result lists what it actually saw. It is a
transparent heuristic, not a trained hazard model. It proposes; you dispose — every
field stays editable and nothing is published until you tap **Post report**.

> **Simulator note:** Vision's scene classifier does not run in the iOS Simulator
> (its Core ML backend fails with "could not create espresso context"). The app
> detects this, falls back to colour analysis alone, caps confidence lower and says
> so in the results. On a real device both signals are used.

Flip **Use backend for AI triage** in the DPW tab to route photos to the FastAPI +
Gemini endpoint in `backend/` for a real multimodal model. If that call fails, the
app falls back to on-device analysis and tells you why.

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

### Sharing to Nextdoor

After you post a report, the app offers to cross-post it to your Nextdoor
neighborhood. It opens Nextdoor's own post composer with the text written for you
— hazard, severity, road status, town, and a downed-wire safety line — and you
review and post it there. The same option lives on every report's detail screen.
Turn the prompt off in **DPW → Neighborhood sharing**.

This uses Nextdoor's [Share Plugin](https://developer.nextdoor.com/reference/share-plugin)
(`https://nextdoor.com/sharekit/`), which is an open offering: no API key, no
approval, no account linking.

**It is not fully automatic, and it cannot be.** Nextdoor's other option, the
[Publish API](https://developer.nextdoor.com/docs/sharing-overview), can post
natively, but it requires applying for access and OAuth-linking each user's
Nextdoor account — and Nextdoor still requires the post to originate from a real
Nextdoor user (a neighbor, business, or public agency) rather than from the
partner platform. If StormWatch NJ is ever adopted by a town as a Nextdoor Public
Agency, `NextdoorShare` is the seam to swap for that API.

Two limitations worth knowing:

- **The photo is not carried over.** The Share Plugin takes text only, which is
  consistent with the app's promise that photos stay on your device.
- **The precise coordinate is not included** — only the municipality and your
  description, since a Nextdoor post is public to the whole neighborhood.

### Location

The app needs a New Jersey location to show anything — the radius filter is the
whole point. It handles every case rather than showing an empty map:

| Situation | Behaviour |
| --- | --- |
| Real fix inside NJ | Uses it. |
| Real fix outside NJ | Falls back to the Plainsboro demo area and says so. |
| Permission denied or not yet granted | Falls back, with an **Allow** button on the map. |

This matters in the simulator, whose default location is Cupertino — over 2,000
miles outside any 5-mile radius. To simulate a real NJ position:

```bash
xcrun simctl location "iPhone 17 Pro" set 40.3318,-74.5893
```

Or in the Simulator: **Features → Location → Custom Location**.

### Debug-only launch arguments

`Debug` builds accept two arguments used by the screenshot pass. They are compiled
out of `Release` entirely.

```bash
xcrun simctl launch "iPhone 17 Pro" com.stormwatchnj.StormWatchNJ \
  -startTab 2 -demoScene floodedRoad
```

- `-startTab 0…4` — open a given tab on launch
- `-demoScene floodedRoad|downedTree` — load a sample scene and run triage

### App icon

`Assets.xcassets/AppIcon.appiconset/AppIcon.png` is drawn in code so it is
reproducible and reviewable in the diff:

```bash
swift Tools/make_app_icon.swift StormWatchNJ/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Privacy

Photos stay on the device; only the fields you confirm are published. Your location is
attached to a report only when you submit one, and is never uploaded on its own.
