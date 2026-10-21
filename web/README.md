# StormWatch NJ — web version

The same app as the iPhone version, rebuilt for the browser so it can be tried
from a link. On a computer it appears inside an iPhone frame; on a phone it fills
the screen. It uses the same Supabase backend, so accounts and shared hazards are
the same on both.

## Run it locally

```bash
cd web
npm install
npm run dev
```

## Deploy on Vercel

1. Push the repository to GitHub.
2. In Vercel, **Add New → Project** and import the `StormWatchNJ` repository.
3. Set **Root Directory** to `web`. Vercel detects Vite; the defaults are right
   (build `npm run build`, output `dist`).
4. Deploy.

The Supabase address and publishable key are in `src/app/lib/config.ts`; the
publishable key is designed to be public. Secrets (the OpenAI key) stay on the
server. The only environment variable is the optional Google one below.

**After deploying**, add the Vercel address in Supabase under
*Authentication → URL Configuration*: set it as the **Site URL** (or add it to the
**Redirect URLs**), so links in confirmation emails come back to the site.

## Google sign-in

The web uses Google's own "Continue with Google" button. Google returns an ID
token and Supabase swaps it for a session, the same exchange the iPhone app uses,
so one Google account works on both. Township sign-in with Google follows the same
rule as email: the Google address must be on a listed municipal domain.

It needs a Google OAuth client of type **Web application** (the iPhone client
can't be used on a website):

1. Google Cloud Console → **APIs & Services → Credentials → Create credentials →
   OAuth client ID** → type **Web application**.
2. **Authorized JavaScript origins**: your Vercel address (for example
   `https://stormwatch-nj.vercel.app`) and `http://localhost:5174`. Redirect URIs
   aren't needed.
3. Supabase → **Authentication → Sign In / Providers → Google** → **Client IDs**:
   add the new web client ID after the iPhone one, separated by a comma. Save.
4. Vercel → the project → **Settings → Environment Variables**: add
   `VITE_GOOGLE_CLIENT_ID` = the web client ID. Redeploy.
   (Locally, put the same line in `web/.env.local`.)

Until the variable is set, the button is hidden. If the site's address isn't in
the client's JavaScript origins, the button explains that Google isn't switched on
for that address.

## Notifications

The same three notifications as the iPhone app, with the same rules and toggles in
**Settings → Notifications**: a flood alert where you are, an impassable hazard or
downed wires inside your radius, and updates to your own reports. The site checks
for changes every minute and for flood alerts every five minutes while it's open
(in a tab or installed as an app), and a small service worker (`public/sw.js`)
shows them and opens the right tab when one is tapped.

On iPhone, Safari only allows notifications for sites added to the Home Screen
(Share → Add to Home Screen). The site has an install manifest for that, and
Settings tells iPhone visitors to do it.

## Differences from the iPhone app

| | iPhone app | Web version |
| --- | --- | --- |
| Without an account | Not allowed | **Try the demo without an account** — sample hazards, live public data, and the shared map read-only. Guests' reports stay in their browser. |
| Photo analysis | OpenAI, on-device fallback | Same; guests get the in-browser colour analysis, since OpenAI calls require an account |
| Camera | Live camera or photo library | Same, through the browser |
| Notifications | Also in the background | While the site is open or installed; on iPhone, only once added to the Home Screen |
| Maps | Apple Maps | OpenStreetMap |
| Address lookup | Apple's geocoder | OpenStreetMap Nominatim |
| Google sign-in | Built in | Built in, once `VITE_GOOGLE_CLIENT_ID` is set (see above) |

The guest mode exists because signing up needs an emailed code, and Supabase's
built-in mailer sends only a few emails an hour — judges trying the site at once
would be locked out. Remove the button in `screens/Welcome.tsx` to require
accounts, as the iPhone app does.

Map tiles come from OpenStreetMap's public tile server, which is fine for a demo.
For heavy traffic, switch the tile URL in `MapScreen.tsx` and `HazardDetail.tsx` to
a provider with an API key.
