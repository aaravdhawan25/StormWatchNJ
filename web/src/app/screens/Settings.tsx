import { Bell, Building2, EyeOff, Globe, House, LogOut, MapPin, Sparkles, User } from "lucide-react";
import { Header, Toggle, useNav } from "../components/ui";
import { useStore } from "../lib/store";

export function SettingsScreen() {
  const s = useStore();
  const nav = useNav();
  const a = s.account!;
  const township = a.role === "township";
  const subtitle = a.guest ? "Guest demo" : township ? `${a.township ?? "Township"} · verified staff` : "Resident";

  return (
    <div className="screen">
      <Header title="Settings" subtitle={subtitle} />
      <div className="scroll">
        <div className="group">
          <div className="cell" style={{ flexDirection: "column", padding: "18px 16px", gap: 8 }}>
            <div style={{ width: 72, height: 72, borderRadius: 36, display: "grid", placeItems: "center", color: "#fff",
              background: "linear-gradient(135deg, var(--deep), var(--teal))", boxShadow: "0 4px 10px rgba(23,158,176,.4)" }}>
              {township ? <Building2 size={30} /> : <User size={30} />}
            </div>
            <b className="rounded">{a.guest ? "Guest" : a.email}</b>
            <span className="chip" style={{ background: "rgba(23,158,176,.14)", color: "var(--teal)" }}>
              {township ? <Building2 size={11} /> : <House size={11} />} {subtitle}</span>
          </div>
          <button className="cell danger" onClick={() => nav.dialog({
            title: a.guest ? "Leave the demo?" : "Sign out of StormWatch NJ?",
            message: a.guest ? "You'll return to the welcome screen." : "You'll need to sign in again to use the app.",
            actions: [{ label: "Cancel" }, { label: a.guest ? "Leave" : "Sign out", danger: true, run: () => s.signOut() }] })}>
            <LogOut size={17} /> {a.guest ? "Leave the demo" : "Sign out"}
          </button>
        </div>
        <p className="group-foot">
          {a.guest ? "In the guest demo, reports you post stay in this browser. Create an account to share them with your neighbors and town."
            : township ? "Township accounts can set crew status on any hazard and remove hazards once they are cleared."
            : "You can remove hazards you reported, and vote when someone else's is no longer there. Three votes from different people remove it."}
        </p>

        <div className="group-head">Notifications</div>
        <div className="group">
          <div className="cell"><Bell size={18} color="var(--teal)" /> <span className="small">Flood alerts, nearby hazards and updates on your reports</span></div>
        </div>
        <p className="group-foot">Notifications come from the StormWatch NJ iPhone app. In this web demo, live flood alerts show as a banner on the map instead.</p>

        <div className="group-head">Your area</div>
        <div className="group">
          <div className="cell" style={{ flexDirection: "column", alignItems: "stretch", gap: 8 }}>
            <div className="row"><span>Search radius</span><span className="val">{s.settings.radiusMiles} mi</span></div>
            <input type="range" min={1} max={25} step={1} value={s.settings.radiusMiles} style={{ accentColor: "var(--teal)" }}
                   onChange={e => s.updateSettings({ radiusMiles: Number(e.target.value) })} />
          </div>
          <div className="cell"><MapPin size={17} /> <span>Location</span><span className="val small">{s.locationText}</span></div>
        </div>
        <p className="group-foot">The map and the Nearby list use this radius around where you are.</p>

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
        <p className="group-foot">Each photo you take is sent to OpenAI once to read the scene and fill in the report. It is not stored by StormWatch or shown to anyone. If OpenAI can't be reached — or in the guest demo — a simpler in-browser analysis is used. Who filed a report is never shown to other people.</p>

        <div className="group-head">Demo</div>
        <div className="group">
          <div className="cell">Simulate nor'easter <Toggle on={s.simulating} onChange={s.setSimulating} /></div>
          <button className="cell" style={{ color: "var(--red)" }} onClick={() => nav.dialog({
            title: "Reset all reports to the seeded demo set?", actions: [{ label: "Cancel" }, { label: "Reset reports", danger: true, run: s.resetDemo }] })}>
            Reset to seeded demo reports</button>
        </div>
        <p className="group-foot">The simulation adds clearly-labelled simulated hazards and pushes every river gauge past flood stage, so the map and alerts can be shown on a clear day. Seeded reports are fictional sample data, not records of real incidents.</p>

        <div className="group-head">About</div>
        <div className="group">
          <div className="cell"><span>Version</span><span className="val">1.0 (web)</span></div>
          <a className="cell link" href="https://www.weather.gov/safety/flood" target="_blank" rel="noreferrer"><Globe size={17} /> Flood safety from the National Weather Service</a>
        </div>
        <p className="group-foot">StormWatch NJ is a community tool. In an emergency, call 911.</p>
      </div>
    </div>
  );
}
