import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import { DEMO_CENTER, functionURL, inNJ, supabase, SUPABASE_KEY } from "./config";
import { nearestTown, seedHazards, stormSurgeHazards } from "./demoData";
import type { Hazard, ReportStatus } from "./models";
import { milesBetween } from "./models";
import { fetchGauges, fetchLiveAlerts, gaugeAlert, reverseGeocode, STATIONS, type FloodAlert, type Station } from "./publicData";

export type LocationMode = "live" | "waiting" | "denied" | "outside";
export interface Account { id: string; email: string; role: "resident" | "township"; township?: string | null; guest?: boolean }

interface Settings { radiusMiles: number; offerNextdoor: boolean }

interface Store {
  account: Account | null;
  authReady: boolean;
  session: Session | null;
  enterGuest: () => void;
  signOut: () => Promise<void>;

  hazards: Hazard[];
  nearby: (radius?: number) => Hazard[];
  refreshHazards: () => Promise<void>;
  report: (h: Omit<Hazard, "id" | "shared" | "createdAt" | "updatedAt" | "status" | "upvotes">) => Promise<Hazard>;
  voteNotThere: (h: Hazard) => Promise<boolean>;
  remove: (h: Hazard) => Promise<void>;
  setStatus: (h: Hazard, s: ReportStatus) => Promise<void>;
  confirmHazard: (h: Hazard) => void;

  location: { latitude: number; longitude: number };
  locationMode: LocationMode;
  locationText: string;

  settings: Settings;
  updateSettings: (s: Partial<Settings>) => void;

  stations: Station[];
  gaugesUpdated?: Date;
  gaugesError?: string;
  refreshGauges: () => Promise<void>;
  liveAlerts: FloodAlert[];

  simulating: boolean;
  setSimulating: (on: boolean) => void;
  resetDemo: () => void;
}

const Ctx = createContext<Store | null>(null);
export const useStore = () => useContext(Ctx)!;

const SETTINGS_KEY = "stormwatch-web-settings";
const GUEST_KEY = "stormwatch-web-guest";
const LOCAL_KEY = "stormwatch-web-local-hazards";

function loadSettings(): Settings {
  try { return { radiusMiles: 5, offerNextdoor: true, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) ?? "{}") }; }
  catch { return { radiusMiles: 5, offerNextdoor: true }; }
}

function loadLocal(): Hazard[] {
  try {
    const saved = JSON.parse(localStorage.getItem(LOCAL_KEY) ?? "null");
    return Array.isArray(saved) ? saved : seedHazards();
  } catch { return seedHazards(); }
}

// Rows from the database and the GeoJSON feed.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Row = any;

function fromServer(r: Row): Hazard {
  return {
    id: r.id, reportType: r.report_type, severity: r.severity, roadStatus: r.road_status,
    utilityLinesInvolved: r.utility_lines_involved, details: r.description,
    latitude: r.latitude, longitude: r.longitude, municipality: r.municipality ?? "New Jersey",
    address: r.address, zipcode: r.zipcode, status: r.status, upvotes: r.upvotes ?? r.confirmations ?? 1,
    createdAt: r.created_at, updatedAt: r.updated_at, shared: true,
    isMine: r.is_mine, notThereVotes: r.not_there_votes, iVotedNotThere: r.i_voted_not_there,
  };
}

export function StoreProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [guest, setGuest] = useState(() => localStorage.getItem(GUEST_KEY) === "1");
  const [profile, setProfile] = useState<{ role: "resident" | "township"; township?: string | null } | null>(null);

  const [local, setLocal] = useState<Hazard[]>(loadLocal);
  const [shared, setShared] = useState<Hazard[]>([]);
  const [settings, setSettings] = useState<Settings>(loadSettings);
  const [simulating, setSimulatingState] = useState(false);

  const [location, setLocation] = useState(DEMO_CENTER);
  const [locationMode, setLocationMode] = useState<LocationMode>("waiting");

  const [stations, setStations] = useState<Station[]>(STATIONS);
  const [gaugesUpdated, setGaugesUpdated] = useState<Date>();
  const [gaugesError, setGaugesError] = useState<string>();
  const [liveAlerts, setLiveAlerts] = useState<FloodAlert[]>([]);
  const photos = useRef(new Map<string, string>());

  // ---- auth
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setAuthReady(true); });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) { setProfile(null); return; }
    supabase.from("profiles").select("role,township").maybeSingle().then(({ data }) =>
      setProfile(data ? { role: data.role, township: data.township } : { role: "resident" }));
  }, [session]);

  const account: Account | null = session
    ? { id: session.user.id, email: session.user.email ?? "", role: profile?.role ?? "resident", township: profile?.township }
    : guest ? { id: "guest", email: "Guest", role: "resident", guest: true } : null;

  const enterGuest = () => { localStorage.setItem(GUEST_KEY, "1"); setGuest(true); };
  const signOut = async () => {
    localStorage.removeItem(GUEST_KEY); setGuest(false);
    if (session) await supabase.auth.signOut();
    setShared([]);
  };

  // ---- location: a real fix inside New Jersey, otherwise the Plainsboro demo area
  useEffect(() => {
    if (!navigator.geolocation) { setLocationMode("denied"); return; }
    navigator.geolocation.getCurrentPosition(
      pos => {
        const p = { latitude: pos.coords.latitude, longitude: pos.coords.longitude };
        if (inNJ(p)) { setLocation(p); setLocationMode("live"); } else setLocationMode("outside");
      },
      () => setLocationMode("denied"),
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 600000 },
    );
  }, []);
  const locationText = {
    live: "Using your current location.",
    waiting: "Finding you — showing the Plainsboro demo area.",
    denied: "Location is off — showing the Plainsboro demo area.",
    outside: "You're outside New Jersey — showing the Plainsboro demo area.",
  }[locationMode];

  // ---- hazards
  useEffect(() => { localStorage.setItem(LOCAL_KEY, JSON.stringify(local.filter(h => !h.simulated).map(({ photoURL: _p, ...h }) => h))); }, [local]);

  const refreshHazards = useCallback(async () => {
    if (session) {
      const { data } = await supabase.rpc("list_hazards");
      if (data) setShared((data as Row[]).map(fromServer));
    } else if (guest) {
      // Guests read the same shared hazards through the public GIS feed.
      try {
        const feed = await (await fetch(functionURL("hazard-feed"))).json();
        setShared(feed.features.map((f: Row) => fromServer({ ...f.properties, id: f.id,
          latitude: f.geometry.coordinates[1], longitude: f.geometry.coordinates[0], description: f.properties.description })));
      } catch { /* keep what we have */ }
    }
  }, [session, guest]);
  useEffect(() => { refreshHazards(); }, [refreshHazards]);

  const hazards = useMemo(() => [...local, ...shared].map(h => photos.current.has(h.id) ? { ...h, photoURL: photos.current.get(h.id) } : h)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt)), [local, shared]);

  const nearby = useCallback((radius = settings.radiusMiles) => hazards
    .filter(h => h.status !== "RESOLVED")
    .map(h => ({ h, d: milesBetween(location, h) }))
    .filter(x => x.d <= radius)
    .sort((a, b) => a.d - b.d)
    .map(x => x.h), [hazards, location, settings.radiusMiles]);

  const report: Store["report"] = async draft => {
    const place = await reverseGeocode(draft.latitude, draft.longitude);
    const now = new Date().toISOString();
    if (session) {
      const form = new URLSearchParams({
        service_code: draft.reportType, lat: String(draft.latitude), long: String(draft.longitude),
        description: draft.details, "attribute[severity]": draft.severity, "attribute[road_status]": draft.roadStatus,
        "attribute[utility_lines_involved]": String(draft.utilityLinesInvolved), "attribute[municipality]": draft.municipality,
      });
      if (place?.line) form.set("address_string", place.line);
      if (place?.zip) form.set("attribute[zipcode]", place.zip);
      const res = await fetch(functionURL("georeport/requests.json"), {
        method: "POST", body: form,
        headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${session.access_token}`, "Content-Type": "application/x-www-form-urlencoded" },
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body?.[0]?.description ?? "Couldn't send the report.");
      const id = body[0].service_request_id;
      if (draft.photoURL) photos.current.set(id, draft.photoURL);
      await refreshHazards();
      return hazards.find(h => h.id === id) ?? { ...draft, id, shared: true, isMine: true, status: "ACTIVE", upvotes: 1, createdAt: now, updatedAt: now };
    }
    // Guests: kept in this browser only.
    const h: Hazard = { ...draft, id: `local-${Date.now()}`, shared: false, isMine: true, status: "ACTIVE", upvotes: 1,
                        createdAt: now, updatedAt: now, address: place?.line, zipcode: place?.zip };
    if (draft.photoURL) photos.current.set(h.id, draft.photoURL);
    setLocal(l => [h, ...l]);
    return h;
  };

  const voteNotThere = async (h: Hazard) => {
    const { data, error } = await supabase.rpc("vote_not_there", { p_hazard: h.id });
    if (error) throw new Error(error.message);
    await refreshHazards();
    return (data as { removed: boolean }).removed;
  };

  const remove = async (h: Hazard) => {
    if (!h.shared) { setLocal(l => l.filter(x => x.id !== h.id)); return; }
    const { error } = await supabase.rpc("remove_hazard", { p_hazard: h.id });
    if (error && error.code !== "P0002") throw new Error(error.message);
    await refreshHazards();
  };

  const setStatus = async (h: Hazard, s: ReportStatus) => {
    if (!h.shared) { setLocal(l => l.map(x => x.id === h.id ? { ...x, status: s } : x)); return; }
    const { error } = await supabase.rpc("set_hazard_status", { p_hazard: h.id, p_status: s });
    if (error) throw new Error(error.message);
    await refreshHazards();
  };

  const confirmHazard = (h: Hazard) => {
    const bump = (x: Hazard) => x.id === h.id ? { ...x, upvotes: x.upvotes + 1 } : x;
    if (h.shared) setShared(s => s.map(bump)); else setLocal(l => l.map(bump));
  };

  // ---- gauges and live alerts
  const refreshGauges = useCallback(async () => {
    if (simulating) return;
    try { setStations(await fetchGauges()); setGaugesUpdated(new Date()); setGaugesError(undefined); }
    catch (e) { setGaugesError((e as Error).message); }
  }, [simulating]);
  useEffect(() => { if (account) refreshGauges(); }, [account?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!account) return;
    fetchLiveAlerts(location.latitude, location.longitude).then(setLiveAlerts).catch(() => setLiveAlerts([]));
  }, [account?.id, location.latitude, location.longitude]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---- demo
  const setSimulating = (on: boolean) => {
    setSimulatingState(on);
    if (on) {
      setLocal(l => [...stormSurgeHazards(), ...l]);
      setStations(st => st.map(s => ({ ...s, heightFt: +(s.floodStageFt + 0.2 + Math.random() * 1.2).toFixed(2), readingTime: new Date().toISOString() })));
    } else {
      setLocal(l => l.filter(h => !h.simulated));
      fetchGauges().then(setStations).catch(() => setStations(STATIONS));
    }
  };
  const resetDemo = () => {
    if (simulating) setSimulating(false);
    setLocal(seedHazards());
  };

  const updateSettings = (s: Partial<Settings>) => setSettings(prev => {
    const next = { ...prev, ...s };
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(next));
    return next;
  });

  const value: Store = {
    account, authReady, session, enterGuest, signOut,
    hazards, nearby, refreshHazards, report, voteNotThere, remove, setStatus, confirmHazard,
    location, locationMode, locationText, settings, updateSettings,
    stations, gaugesUpdated, gaugesError, refreshGauges, liveAlerts,
    simulating, setSimulating, resetDemo,
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export const townFor = nearestTown;
export const alertOf = gaugeAlert;
