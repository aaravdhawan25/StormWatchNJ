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

No environment variables are needed. The Supabase address and publishable key are
in `src/app/lib/config.ts`; the publishable key is designed to be public. Secrets
(the OpenAI key) stay on the server.

**After deploying**, add the Vercel address in Supabase under
*Authentication → URL Configuration*: set it as the **Site URL** (or add it to the
**Redirect URLs**), so links in confirmation emails come back to the site.

## Differences from the iPhone app

| | iPhone app | Web version |
| --- | --- | --- |
| Without an account | Not allowed | **Try the demo without an account** — sample hazards, live public data, and the shared map read-only. Guests' reports stay in their browser. |
| Photo analysis | OpenAI, on-device fallback | Same; guests get the in-browser colour analysis, since OpenAI calls require an account |
| Camera | Live camera | The phone's camera or a file picker, through the browser |
| Notifications | Yes | No — live flood alerts show as a banner on the map |
| Maps | Apple Maps | OpenStreetMap |
| Address lookup | Apple's geocoder | OpenStreetMap Nominatim |
| Google sign-in | Built in | Off. Turning it on needs a **Web** OAuth client in Supabase's Google provider, then `VITE_ENABLE_GOOGLE=true` in Vercel |

The guest mode exists because signing up needs an emailed code, and Supabase's
built-in mailer sends only a few emails an hour — judges trying the site at once
would be locked out. Remove the button in `screens/Welcome.tsx` to require
accounts, as the iPhone app does.

Map tiles come from OpenStreetMap's public tile server, which is fine for a demo.
For heavy traffic, switch the tile URL in `MapScreen.tsx` and `HazardDetail.tsx` to
a provider with an API key.
