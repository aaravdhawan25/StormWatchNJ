import { useState } from "react";
import { Bell, BellOff, Building2, ChevronRight, CircleUser, EyeOff, Globe, House, Landmark, LocateFixed, LogOut, MapPin, RotateCcw, Sparkles, User } from "lucide-react";
import { loadPrefs, permission, requestPermission, savePrefs, type NotifyPrefs } from "../lib/notifications";
import { Header, NavBar, Toggle, useNav } from "../components/ui";
import { useStore } from "../lib/store";

export function SettingsScreen() {
  const s = useStore();
  const nav = useNav();
  const a = s.account!;
  const township = a.role === "township";
  const [prefs, setPrefs] = useState(loadPrefs);
  const [allowed, setAllowed] = useState(permission);
  const setPref = (k: keyof NotifyPrefs, v: boolean) => { const next = { ...prefs, [k]: v }; setPrefs(next); savePrefs(next); };
  const standalone = window.matchMedia?.("(display-mode: standalone)").matches;
  const iPhone = /iPhone|iPad|iPod/.test(navigator.userAgent);
  const subtitle = a.guest ? "Guest demo" : township ? `${a.township ?? "Township"} · verified staff` : "Resident";

  return (
    <div className="screen">
      <Header title="Settings" subtitle={subtitle} />
      <div className="scroll">
        <div className="group">
          <button className="cell" onClick={() => nav.push(<AccountScreen />)} style={{ gap: 12 }}>
            {township ? <Landmark size={26} color="var(--teal)" /> : <CircleUser size={26} color="var(--teal)" />}
            <div style={{ flex: 1, minWidth: 0, textAlign: "left" }}>
              <div style={{ fontWeight: 600, fontSize: 15, overflow: "hidden", textOverflow: "ellipsis" }}>{a.guest ? "Guest" : a.email}</div>
              <div className="small muted">{subtitle}</div>
            </div>
            <ChevronRight size={16} color="var(--faint)" />
          </button>
        </div>

        <div className="group-head">Notifications</div>
        <div className="group">
          {allowed === "granted" ? <>
            <div className="cell">Flood alerts where I am <Toggle on={prefs.flood} onChange={v => setPref("flood", v)} /></div>
            <div className="cell">Impassable roads and downed wires nearby <Toggle on={prefs.nearby} onChange={v => setPref("nearby", v)} /></div>
            <div className="cell">Updates on my reports <Toggle on={prefs.mine} onChange={v => setPref("mine", v)} /></div>
          </> : allowed === "denied" ? (
            <div className="cell"><BellOff size={18} color="var(--red)" /> <span className="small">Notifications are off — allow them for this site in your browser's settings</span></div>
          ) : allowed === "unsupported" ? (
            <div className="cell"><BellOff size={18} color="var(--muted)" /> <span className="small">
              {iPhone && !standalone ? "On iPhone, tap Share → Add to Home Screen, then open StormWatch from there to turn on notifications." : "This browser can't show notifications."}</span></div>
          ) : (
            <button className="cell link" onClick={async () => setAllowed(await requestPermission())}><Bell size={18} /> Turn on notifications</button>
          )}
        </div>
        <p className="group-foot">StormWatch checks for these while it's open in a tab or installed as an app, so they can arrive late and won't arrive at all once it's closed. For life-safety warnings, keep Emergency Alerts on in your phone's settings.</p>

        <div className="group-head">Your area</div>
        <div className="group">
          <div className="cell" style={{ flexDirection: "column", alignItems: "stretch", gap: 8 }}>
            <div className="row"><span>Search radius</span><span className="val">{s.settings.radiusMiles} mi</span></div>
            <input type="range" min={1} max={25} step={1} value={s.settings.radiusMiles} style={{ accentColor: "var(--teal)" }}
                   onChange={e => s.updateSettings({ radiusMiles: Number(e.target.value) })} />
          </div>
          <div className="cell"><MapPin size={17} /> <span>Location</span><span className="val small">{s.locationText}</span></div>
          {s.locationMode === "denied" && (
            <div className="cell link"><LocateFixed size={17} /> <span className="small">Turn on location for this site in your browser's settings</span></div>
          )}
        </div>
        <p className="group-foot">The map, the Nearby list and hazard notifications all use this radius around where you are.</p>

        <div className="group-head">Neighborhood sharing</div>
        <div className="group">
          <div className="cell">Offer Nextdoor share after posting <Toggle on={s.settings.offerNextdoor} onChange={v => s.updateSettings({ offerNextdoor: v })} /></div>
        </div>
        <p className="group-foot">After you post a report, StormWatch NJ offers to open Nextdoor's composer with the details written for you. You review and post it there — nothing is ever sent to Nextdoor automatically, and the photo is not included.</p>

        <div className="group-head">Photos and privacy</div>
        <div className="group">
          <div className="cell"><Sparkles size={18} color="var(--teal)" /> Photos are analyzed by OpenAI</div>
          <div className="cell"><EyeOff size={18} color="var(--teal)" /> Photos are never published</div>
          <div className="cell"><MapPin size={18} color="var(--teal)" /> Your location is shared only with a report</div>
        </div>
        <p className="group-foot">Each photo you take is sent to OpenAI once to read the scene and fill in the report. It is not stored by StormWatch or shown to anyone. If OpenAI can't be reached, a simpler on-device analysis is used so you can still file. Who filed a report is never shown to other people.</p>

        <div className="group-head">Demo</div>
        <div className="group">
          <div className="cell">Simulate nor'easter <Toggle on={s.simulating} onChange={s.setSimulating} /></div>
        </div>
        <p className="group-foot">Adds clearly-labelled simulated hazards and pushes every river gauge past flood stage, so the map and alerts can be filmed on a clear day. Turn it off to return to live USGS data.</p>

        <div className="group">
          <button className="cell" style={{ color: "var(--red)" }} onClick={() => nav.dialog({
            title: "Reset all reports to the seeded demo set?", actions: [{ label: "Reset reports", danger: true, run: s.resetDemo }, { label: "Cancel" }] })}>
            <RotateCcw size={17} /> Reset to seeded demo reports</button>
        </div>
        <p className="group-foot">Seeded reports are fictional sample data for testing, not records of real incidents.</p>

        <div className="group-head">About</div>
        <div className="group">
          <div className="cell"><span>Version</span><span className="val">1.0</span></div>
          <a className="cell link" href="https://www.weather.gov/safety/flood" target="_blank" rel="noreferrer"><Globe size={17} /> Flood safety from the National Weather Service</a>
        </div>
        <p className="group-foot">StormWatch NJ is a community tool. In an emergency, call 911.</p>
      </div>
    </div>
  );
}

// who is signed in, what that lets them do, and the way out, as on iPhone
function AccountScreen() {
  const s = useStore();
  const nav = useNav();
  const a = s.account!;
  const township = a.role === "township";
  const chip = a.guest ? "Guest demo" : township ? `${a.township ?? "Township"} · verified staff` : "Resident";
  return (
    <>
      <NavBar title="Account" />
      <div className="scroll">
        <div className="group">
          <div className="cell" style={{ flexDirection: "column", padding: "20px 16px", gap: 10 }}>
            <div style={{ width: 72, height: 72, borderRadius: 36, display: "grid", placeItems: "center", color: "#fff",
              background: "linear-gradient(135deg, var(--deep), var(--teal))", boxShadow: "0 4px 10px rgba(23,158,176,.4)" }}>
              {township ? <Building2 size={30} /> : <User size={30} />}
            </div>
            <b className="rounded">{a.guest ? "Guest" : a.email}</b>
            <span className="chip" style={{ background: "rgba(23,158,176,.14)", color: "var(--teal)" }}>
              {township ? <Building2 size={11} /> : <House size={11} />} {chip}</span>
          </div>
        </div>
        <p className="group-foot">
          {a.guest ? "In the guest demo, reports you post stay in this browser. Create an account to share them with your neighbors and town."
            : township ? "Township accounts can set crew status on any hazard and remove hazards once they are cleared."
            : "You can remove hazards you reported, and vote when someone else's is no longer there. Three votes from different people remove it."}
        </p>
        <div className="group">
          <button className="cell danger" style={{ justifyContent: "center" }} onClick={() => nav.dialog({
            title: a.guest ? "Leave the demo?" : "Sign out of StormWatch NJ?",
            message: a.guest ? "You'll return to the welcome screen." : "You'll need to sign in again to use the app.",
            actions: [{ label: a.guest ? "Leave" : "Sign out", danger: true, run: () => s.signOut() }, { label: "Cancel" }] })}>
            <LogOut size={17} /> {a.guest ? "Leave the demo" : "Sign out"}
          </button>
        </div>
      </div>
    </>
  );
}
