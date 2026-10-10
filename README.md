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

## Backend

The app is fully functional without it. Run it for Gemini triage and the municipal
hand-offs:

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Set the backend URL in the DPW tab to `http://127.0.0.1:8000` (simulator) or
`http://<your-mac-ip>:8000` (physical device). Reports are stored in SQLite so there
is nothing else to install; `schema.sql` is the PostgreSQL + PostGIS production target.

| Endpoint | What it is |
| --- | --- |
| `POST /georeport/v2/requests.json` | Open311: file a report (form-encoded, as the spec requires) |
| `GET /georeport/v2/requests.json` | Open311: list reports; filter by `status`, `service_code`, dates |
| `GET /georeport/v2/services.json` | Open311: the hazard types, with attribute definitions per service |
| `GET /api/v1/hazards/feed.geojson` | Live GIS layer — add by URL in ArcGIS Online or QGIS |
| `POST /api/v1/integrations/dispatch-alert` | Re-send a stored report to its town |
| `POST /api/v1/auth/signup`, `/verify`, `/login`, `/google` | Accounts; `GET /api/v1/auth/township-domains` lists recognised towns |
| `GET /api/v1/hazards` | The shared hazard list the app syncs from |
| `POST /api/v1/hazards/{id}/not-there` | Vote that a hazard is gone; the third distinct vote removes it |
| `DELETE /api/v1/hazards/{id}` | Remove — reporter or township only |
| `PATCH /api/v1/hazards/{id}/status` | Crew status — township only |
| `POST /api/v1/analyze-image` | Gemini triage (needs `GOOGLE_API_KEY`) |

**Forwarding to a town.** Copy `dispatch_config.example.json` to
`dispatch_config.json` and add a town by ZIP code with a `webhook_url`, an `email`,
or both. There are no built-in destinations: a town opts in by giving you an
address. The desk receives the hazard, severity, street address, GPS, a Google Maps
pin and a plain note that it is an unverified resident report. Email goes through
[Resend](https://resend.com) and is skipped unless `RESEND_API_KEY` and
`DISPATCH_FROM_EMAIL` are set.

**Keeping it from becoming a spam relay.** A second report of the same hazard within
75 m and 6 hours becomes a confirmation on the first ticket rather than a new one.
`min_severity` and `max_per_hour` cap what a desk receives. Reports outside New
Jersey are rejected. Set `STORMWATCH_API_KEYS` before exposing the API — unset, it
runs in open development mode. Reporter name, email and phone are accepted by
Open311 but discarded here, so the public feed cannot leak who filed a report.

Not implemented: XML responses, placing a report from `address_string` alone (there
is no geocoder server-side), and an ESRI Shapefile export — ArcGIS and QGIS both read
the GeoJSON feed directly.

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

### Accounts and removing hazards

Sign in from **DPW → Sign in or create an account**. Accounts live on the backend,
so this needs it running.

A hazard comes off the map — for everyone — in three ways:

| Who | How |
| --- | --- |
| The person who reported it | **Remove for everyone** on the report |
| Three different people | Each taps **It's not there anymore**; the third vote removes it |
| A township account | **Remove for everyone**, and can set crew status |

Voting needs an account so that "three people" means three people: one vote per
account, and the reporter cannot vote on their own report. A removed hazard is
deleted from the live table and disappears from the app, the Open311 endpoint and
the GeoJSON feed; a one-line audit record (what, where, when, why) is kept, because
three accounts being able to erase a hazard without trace would invite abuse.

Reports that were never uploaded — the seeded demo data, anything posted while
signed out with the relay off — exist only on that device and can be removed there.

**Resident accounts** use an email and password, confirmed with a six-digit code
sent to that address.

**Township accounts** are for municipal staff. The email must be on one of the 19
recognised municipal domains in `backend/townships.py`, matched exactly — so
`a@princetonnj.gov.example.com` and `a@notprincetonnj.gov` are refused. The domain
check alone proves nothing, since anyone can type someone else's address; the
account only works once its owner enters the code emailed to it. The domain list
was supplied for this project and has not been checked town by town — review it
before real use.

**Verification email** is sent through [Resend](https://resend.com) when
`RESEND_API_KEY` and `DISPATCH_FROM_EMAIL` are set. Without them the code is written
to the server log instead, which is fine on your own laptop and useless anywhere
else — `/health` reports `email_configured` so you can tell.

**Google sign-in** is built but switched off until you give it an OAuth client,
which has to come from your own Google account:

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials),
   create an OAuth client ID of type **iOS** with bundle ID
   `com.stormwatchnj.StormWatchNJ`.
2. Put the client ID in `StormWatchNJ/Info.plist` under `GoogleClientID`.
3. Set the same ID as `GOOGLE_CLIENT_IDS` for the backend.

The "Continue with Google" button appears once step 2 is done. This path has not
been run end to end, because it cannot be without that client ID.

Passwords are stored as salted scrypt hashes and session tokens only as hashes; the
app keeps its token in the Keychain. Five wrong passwords lock an account for 15
minutes, and a code dies after five wrong guesses. Run the backend behind HTTPS
anywhere but your own machine.

### Utility hand-off for downed wires

When a report involves utility lines — the "Utility lines involved" switch, or the
Downed Wire hazard type — a red life-safety banner pins itself under the header on
the report screen and tops that report's detail screen:

- **Stay back first.** "Do not approach. Stay at least 30 feet back" — PSE&G's
  published distance.
- **Call 911**, then **Call PSE&G** (1-800-436-7734). Other NJ electric utilities
  (JCP&L, Atlantic City Electric, Orange & Rockland) are one tap away, because the
  app cannot reliably know which utility serves an address.
- **"Tell the dispatcher: 305 Fox Run Dr, Plainsboro, NJ 08536"** — the hazard's
  street address, reverse-geocoded, so the caller has it to read out.

Nothing is sent automatically. Utilities do not offer write APIs for outage
tickets, and should not; each button opens the dialer and iOS confirms before a
call is placed. On a device with no dialer the number is shown instead.

Two things this deliberately does **not** do:

- **It does not text the hazard to PSE&G.** PSE&G's text line (`OUT` to 47734)
  reports an outage at the address on the texter's *own* account, from a phone
  already enrolled with `REG`. It cannot report a wire somewhere else, and it takes
  no address. The app offers it only as "my own power is out".
- **It does not pass an address to PSE&G's website.** The outage page takes no
  address parameters, so the link opens the page as-is.

Numbers come from the [NJ OEM utility list](https://www.nj.gov/njoem/plan-prepare/public-utilities.shtml)
and [PSE&G's downed power line page](https://nj.pseg.com/safetyandreliability/electricsafety/downedpowerlines).

### Public works relay

Turn on **DPW → Send my reports to public works** and each report you post is also
filed with the backend over [Open311 GeoReport v2](https://wiki.open311.org/GeoReport_v2/),
the civic standard many 311 systems already speak. From there it joins the open GIS
feed and is forwarded to the town's public works desk — if that town has opted in.
It is off by default, the photo is never sent, and a report that could not be
forwarded can be re-sent from its detail screen.

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
