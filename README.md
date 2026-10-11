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
manager and no server to start; the backend is hosted on Supabase. You'll create an
account on the welcome screen, so the device needs an internet connection the first
time. The app ships with seeded demo reports and pulls live river data on launch.

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
| **Alerts** | Flood alerts for your ZIP, open emergency shelters, and all 11 river gauges with live gage height against flood stage. |
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

**OpenAI vision does the triage.** Every photo goes to the `analyze-image` server
function, which asks an OpenAI vision model (`gpt-4.1-mini`) for a strictly
structured answer. There is no switch to turn it off. The OpenAI key is stored
encrypted in Supabase Vault and read only by the server function; it is never in
the app or this repository.

The on-device engine described above is the fallback: if OpenAI cannot be reached —
no signal, or the service is down — the app uses it instead and says so, so a
resident can still file a report in the middle of a storm.

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

The backend runs on [Supabase](https://supabase.com) — there is no server to start.
Everything that defines it is in `supabase/`:

| Piece | Where | What it does |
| --- | --- | --- |
| Tables | `migrations/0001_schema.sql` | Hazards (PostGIS), votes, profiles, township domains, removal audit, dispatch towns |
| Rules | `migrations/0002_rules.sql` | Reporting, the three-vote rule, removal, crew status, township roles |
| Open311 | `functions/georeport` | GeoReport v2: services, service definitions, GET and POST requests |
| GIS feed | `functions/hazard-feed` | GeoJSON layer — add by URL in ArcGIS Online or QGIS |
| AI triage | `functions/analyze-image` | Photo analysis by OpenAI; key held in Supabase Vault |

**How access is controlled.** Every table has row level security on, with no
policies for app users except reading the town list and your own profile. The app
never reads or writes a table directly; it calls database functions that check who
is asking. So who reported a hazard never reaches another user, and nobody can vote
twice, remove someone else's report, or make themselves a township by calling the
API by hand. The app ships only the publishable key, which grants nothing by itself.

**Open311.** Reads are public. A POST must come from a signed-in user or carry an
`api_key` listed in the `OPEN311_API_KEYS` secret (for a town's own system). A
second report of the same kind of hazard within 75 m and 6 hours becomes a
confirmation instead of a second ticket. Reports outside New Jersey are refused.
Reporter name, email and phone are accepted, as the spec allows, and discarded.

**Forwarding to a town.** Add a row to `dispatch_towns` with the ZIP code and a
`webhook_url`, an `email`, or both. There are no built-in destinations: a town opts
in by giving you an address. The desk receives the hazard, severity, street address,
GPS, a Google Maps pin and a plain note that it is an unverified resident report.
Email needs the `RESEND_API_KEY` and `DISPATCH_FROM_EMAIL` secrets.

**Checks.** `supabase/tests/check_rules.sql` exercises the rules inside a
transaction that rolls back (33 checks). `supabase/tests/check_live.py` exercises the
deployed API over the network (46 checks).

Not implemented: XML responses, placing a report from `address_string` alone (no
geocoder server-side), and an ESRI Shapefile export — ArcGIS and QGIS read the
GeoJSON feed directly.

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
└── supabase/          migrations, server functions, checks
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
  consistent with the app's promise that photos are never published.
- **The precise coordinate is not included** — only the municipality and your
  description, since a Nextdoor post is public to the whole neighborhood.

### Accounts and removing hazards

**Everyone signs in.** The app opens on a welcome screen with three ways in —
create an account, sign in, or sign in as a township — and nothing else is reachable
until one succeeds. Accounts are handled by Supabase Auth. Once signed in, the
session is kept in the Keychain and the app opens straight to the map, including
with no signal.

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

Every report you post goes to the shared map. The seeded demo hazards are the
exception: they exist only on the device, so they can be removed there but not
voted on.

**Resident accounts** use an email and password, confirmed by email.

**Township accounts** are for municipal staff. An account is a township account
only when all three hold: it asked to be one, its email is on one of the 19
recognised municipal domains (matched exactly — `a@princetonnj.gov.example.com` and
`a@notprincetonnj.gov` are refused), and that email has been confirmed. The first
two are things anyone can type; confirmation is what proves the person receives mail
there. This is decided by a database trigger, not by the app, and is recomputed
whenever the account changes. The domain list lives in the `township_domains` table;
it was supplied for this project and has not been checked town by town — review it
before real use.

**Confirmation email.** Supabase sends it. Two things to set in the dashboard:

- *Authentication → Emails → Confirm signup*: add `{{ .Token }}` to the template so
  the email shows a code to type into the app. Without that, the email only has a
  link — which also works: tap it, come back, and choose "I tapped the link".
- Supabase's built-in mailer is limited to a few emails an hour and is meant for
  testing. For real use, add your own SMTP provider under *Authentication → SMTP*.

Keep **Confirm email** switched on. Township security depends on it.

**Google sign-in** is built but switched off until it has an OAuth client, which has
to come from your own Google account:

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials),
   create an OAuth client ID of type **iOS** with bundle ID
   `com.stormwatchnj.StormWatchNJ`.
2. In Supabase, *Authentication → Sign In / Providers → Google*: enable it and add
   that client ID.
3. Put the same client ID in `StormWatchNJ/Info.plist` under `GoogleClientID`.

The "Continue with Google" button appears once step 3 is done. This path has not
been run end to end, because it cannot be without that client ID.

### Flood alerts

**Alerts → Flood alerts** shows flood alerts for a ZIP code — the one you are in by
default, or any New Jersey ZIP you type. It uses two federal sources, because they
answer different questions:

| Source | What it shows |
| --- | --- |
| National Weather Service (`api.weather.gov`) | Alerts in effect **right now**. NWS is the agency that issues flood watches and warnings. |
| FEMA OpenFEMA, [IPAWS Archived Alerts](https://www.fema.gov/openfema-data-page/ipaws-archived-alerts-v1) | Flood warnings issued for that spot in the **past 90 days**. |

FEMA's dataset alone could not do the job: FEMA publishes it with a deliberate
24-hour delay, so it never contains a current warning. It is shown as history and
labelled that way. The FEMA query matches alerts whose drawn area contains the
point, which covers flood *warnings*; county-wide *watches* have no drawn area and
appear only in the live list. When a flood alert is in effect, the map shows a
banner.

### Shelters

**Alerts → Find a shelter** offers two ways to find an open emergency shelter:

- **FEMA's Open Shelters service** — shelters FEMA lists as open within 50 miles,
  nearest first, with directions. On an ordinary day there are none near New Jersey,
  and the screen says so rather than looking broken.
- **FEMA's text line** — a button that opens Messages with `SHELTER <zip>` addressed
  to 43362 (4FEMA). You tap send; FEMA replies by text. This works with no data
  connection, which is when shelters matter most.

The app never sends the text itself. Local officials are the final word on which
shelters are open.

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

Each report you post is filed with the backend over [Open311 GeoReport v2](https://wiki.open311.org/GeoReport_v2/),
the civic standard many 311 systems already speak. From there it joins the open GIS
feed and is forwarded to the town's public works desk — if that town has opted in.
The photo is never sent, and a report that could not be forwarded — posted with
no signal, say — can be re-sent from its detail screen.

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
- `-alertTestPoint "lat,lon"` — check live flood alerts somewhere one is in effect
- `-shelterTestPoint "lat,lon"` — check the shelter list somewhere one is open

### App icon

`Assets.xcassets/AppIcon.appiconset/AppIcon.png` is drawn in code so it is
reproducible and reviewable in the diff:

```bash
swift Tools/make_app_icon.swift StormWatchNJ/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Privacy

Photos are never published or stored by StormWatch; only the fields you confirm go
on the map. Each photo is sent to OpenAI once to read the scene. Your location is
attached to a report only when you submit one, and is never uploaded on its own.
