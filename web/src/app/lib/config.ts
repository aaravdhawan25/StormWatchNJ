import { createClient } from "@supabase/supabase-js";

// The same Supabase project the iPhone app uses. The publishable key is meant
// to be public: it only identifies the project. What a caller may do is
// decided on the server by row level security and the database functions.
export const SUPABASE_URL = "https://yvmmtuqwjvztvxwpmfwf.supabase.co";
export const SUPABASE_KEY = "sb_publishable_J48JNj6IRTzpzwkBsgM_MQ_NmERLY1v";

/** What a confirmation link brought with it, read before Supabase consumes and
 *  clears the address bar. Shown once by the "email confirmed" screen. */
export const emailLink: { ok: boolean; message?: string } | null = (() => {
  const h = new URLSearchParams(window.location.hash.slice(1));
  if (h.get("error_code") || h.get("error")) {
    history.replaceState(null, "", window.location.pathname);
    return { ok: false, message: h.get("error_description") ?? undefined };
  }
  if (h.get("access_token") && ["signup", "email", "email_change"].includes(h.get("type") ?? "")) return { ok: true };
  return null;
})();

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: "stormwatch-web-session" },
});

export const functionURL = (path: string) => `${SUPABASE_URL}/functions/v1/${path}`;
export const FEED_URL = functionURL("hazard-feed");

/** New Jersey's bounding box — the service area, as in the iPhone app. */
export const NJ = { minLat: 38.86, maxLat: 41.4, minLon: -75.61, maxLon: -73.88 };
export const DEMO_CENTER = { latitude: 40.3318, longitude: -74.5893 };
export const inNJ = (p: { latitude: number; longitude: number }) =>
  p.latitude >= NJ.minLat && p.latitude <= NJ.maxLat && p.longitude >= NJ.minLon && p.longitude <= NJ.maxLon;

/** The Google "Web application" OAuth client ID. Its ID must also be listed in
 *  Supabase's Google provider (Client IDs). Without it, the Google button is hidden. */
export const GOOGLE_CLIENT_ID: string = (import.meta.env.VITE_GOOGLE_CLIENT_ID ?? "").trim();
export const GOOGLE_ENABLED = GOOGLE_CLIENT_ID.endsWith(".apps.googleusercontent.com");
