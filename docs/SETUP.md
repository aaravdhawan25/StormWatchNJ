# Setup notes

Everything needed to run, configure and deploy StormWatch NJ. For what the app does,
see the [README](../README.md).

## iPhone app

Open `StormWatchNJ.xcodeproj`, pick an iPhone simulator and press **⌘R**. Requires
Xcode 15 or newer; the app targets iOS 17.

- **Signing.** Automatic signing with bundle ID `com.stormwatchnj.StormWatchNJ`. The
  simulator needs no team. For a real iPhone, choose your team under Signing &
  Capabilities and change the bundle ID to one of your own.
- **Location.** The app needs a New Jersey location. Outside NJ, or with location
  off, it shows the Plainsboro demo area and says so. In the simulator:
  `xcrun simctl location booted set 40.3318,-74.5893`, or **Features → Location →
  Custom Location**.
- **Project file.** `project.pbxproj` is generated. After adding or removing a Swift
  file, run `python3 Tools/generate_xcodeproj.py`.
- **App icon.** Drawn in code:
  `swift Tools/make_app_icon.swift StormWatchNJ/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- **Debug launch arguments** (Debug builds only):
  - `-startTab 0…4` opens a tab on launch.
  - `-demoScene floodedRoad|downedTree` loads a sample scene.
  - `-alertTestPoint "lat,lon"` and `-shelterTestPoint "lat,lon"` check alerts and
    shelters somewhere one is active.

## Website

See [web/README.md](../web/README.md). It deploys on Vercel with **Root Directory**
set to `web`.

## Backend (Supabase)

Everything is in `supabase/`:

| Piece | Where |
| --- | --- |
| Tables | `migrations/0001_schema.sql` |
| Rules: reporting, voting, removal, township roles | `migrations/0002_rules.sql` |
| 3-day expiry and 1-mile voting | `migrations/0005_expiry_and_vote_distance.sql` |
| Website guest limits for AI analysis | `migrations/0006_guest_triage_limit.sql` |
| Open311 GeoReport v2 | `functions/georeport` |
| Public GeoJSON feed | `functions/hazard-feed` |
| OpenAI photo analysis | `functions/analyze-image` |

**Access control.** Every table has row level security. The apps never read or write
tables directly; they call database functions that check who is asking, so nobody
can vote twice, remove someone else's report or make themselves a township by
calling the API by hand.

**OpenAI key.** Stored in Supabase Vault as `openai_api_key` (or the
`OPENAI_API_KEY` function secret). Signed-in users are always allowed. Website
guests are limited to 10 photos an hour each and 300 a day in total.

**Tests.** `supabase/tests/check_rules.sql` checks the rules inside a transaction
that rolls back. `supabase/tests/check_live.py` checks the deployed API.

## Sign-in

**Confirmation emails.** In Supabase, *Authentication → URL Configuration*:

- **Site URL:** the public website address.
- **Redirect URLs:** `stormwatchnj://**`, the website address followed by `/**`,
  and `http://localhost:5174/**`.

The link then goes back to the app or the website, wherever the person signed up.
Keep **Confirm email** on; township accounts depend on it. Supabase's built-in
mailer sends only about 2 emails an hour, so for real use add an SMTP provider
(Resend, Postmark, SendGrid) under *Authentication → Emails → SMTP Settings*.

**Google sign-in.**

1. In Google Cloud Console, create OAuth client IDs: type **iOS** (bundle ID
   `com.stormwatchnj.StormWatchNJ`) for the app, and type **Web application** (with
   the website address as an authorized JavaScript origin) for the website.
2. In Supabase, *Authentication → Sign In / Providers → Google*: enable it and add
   both client IDs, separated by a comma.
3. Put the iOS client ID in `StormWatchNJ/Info.plist` under `GoogleClientID`, and the
   web client ID in the Vercel environment variable `VITE_GOOGLE_CLIENT_ID`.

**Township domains.** The 19 municipal domains are in the `township_domains` table.
The list was supplied for this project and should be checked town by town before
real use.

## Forwarding reports to a town

Add a row to `dispatch_towns` with the town's ZIP code and a `webhook_url`, an
`email`, or both. A town opts in by giving you an address. Email needs the
`RESEND_API_KEY` and `DISPATCH_FROM_EMAIL` secrets. A town's own system can also
post reports over Open311 with an `api_key` listed in the `OPEN311_API_KEYS` secret.
