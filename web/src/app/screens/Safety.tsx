import { useEffect, useState } from "react";
import { CircleCheck, Clock, House, LocateFixed, MapPin, MessageSquare, PawPrint, Accessibility, Radio, ShieldCheck, Navigation } from "lucide-react";
import { NavBar, useNav } from "../components/ui";
import { FEMA_TEXT_NUMBER, HISTORY_DAYS, SHELTER_RADIUS_MILES, alertColor, fetchAlertHistory, fetchLiveAlerts, fetchShelters,
         reverseGeocode, zipToPoint, type FloodAlert, type Shelter } from "../lib/publicData";
import { useStore } from "../lib/store";
import { canCallAndText } from "../lib/device";

// which place a lookup is about: where you are, or a ZIP typed in
function useArea() {
  const { location } = useStore();
  const [zip, setZip] = useState("");
  const [point, setPoint] = useState(location);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const useMine = async () => {
    setPoint(location); setMessage(null);
    const place = await reverseGeocode(location.latitude, location.longitude);
    if (place?.zip) setZip(place.zip);
    return location;
  };
  const useTyped = async () => {
    setBusy(true);
    const p = await zipToPoint(zip);
    setBusy(false);
    if (!p) { setMessage("That isn't a New Jersey ZIP code we can find."); return null; }
    setPoint(p); setMessage(null); return p;
  };
  return { zip, setZip, point, message, busy, useMine, useTyped };
}

function AreaBar({ area, onPoint }: { area: ReturnType<typeof useArea>; onPoint: (p: { latitude: number; longitude: number }) => void }) {
  return (
    <div className="card">
      <div className="row">
        <MapPin size={18} color="var(--teal)" />
        <input value={area.zip} inputMode="numeric" placeholder="ZIP code" maxLength={5}
               onChange={e => area.setZip(e.target.value.replace(/\D/g, "").slice(0, 5))}
               style={{ flex: 1, minWidth: 0, border: 0, outline: "none", fontSize: 20, fontWeight: 700, background: "none" }} />
        <button className="btn primary" style={{ width: "auto", padding: "8px 14px", borderRadius: 99 }} disabled={area.zip.length !== 5 || area.busy}
                onClick={async () => { const p = await area.useTyped(); if (p) onPoint(p); }}>{area.busy ? "…" : "Check"}</button>
        <button className="btn soft" style={{ width: "auto", padding: 9, borderRadius: 99 }} aria-label="Use my location"
                onClick={async () => onPoint(await area.useMine())}><LocateFixed size={17} /></button>
      </div>
      {area.message && <div className="small" style={{ color: "var(--orange)", marginTop: 8 }}>⚠︎ {area.message}</div>}
    </div>
  );
}

export function FloodAlertsScreen() {
  const nav = useNav();
  const area = useArea();
  const [live, setLive] = useState<FloodAlert[] | null>(null);
  const [past, setPast] = useState<FloodAlert[] | null>(null);
  const [liveErr, setLiveErr] = useState<string | null>(null);
  const [pastErr, setPastErr] = useState<string | null>(null);

  const load = (p: { latitude: number; longitude: number }) => {
    setLive(null); setPast(null);
    fetchLiveAlerts(p.latitude, p.longitude).then(a => { setLive(a); setLiveErr(null); }).catch(e => { setLive([]); setLiveErr(e.message); });
    fetchAlertHistory(p.latitude, p.longitude).then(a => { setPast(a); setPastErr(null); }).catch(e => { setPast([]); setPastErr(e.message); });
  };
  useEffect(() => { area.useMine().then(load); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const notice = (text: string, icon: React.ReactNode) => <div className="card row small">{icon}{text}</div>;
  const fmt = (iso?: string) => iso ? new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" }) : "";
  const card = (a: FloodAlert) => (
    <button key={a.id} className="hcard" onClick={() => nav.present(<AlertDetail alert={a} />)}>
      <div className="stripe" style={{ background: alertColor(a.severity) }} />
      <div style={{ padding: 12, flex: 1, textAlign: "left" }}>
        <div className="row"><b className="rounded">{a.event}</b><span className="spacer" />
          <span className="badge" style={{ background: alertColor(a.severity) + "2e", color: alertColor(a.severity) }}>{a.severity.toUpperCase()}</span></div>
        <div className="small muted clamp2" style={{ margin: "4px 0" }}>{a.area}</div>
        <div className="tiny muted">{a.live ? (a.expires ? `Until ${fmt(a.expires)}` : "In effect") : `Issued ${fmt(a.sent)}`}</div>
      </div>
    </button>
  );

  return (
    <>
      <NavBar title="Flood Alerts" />
      <div className="scroll"><div className="stack">
        <AreaBar area={area} onPoint={load} />
        <div className="section-title"><Radio size={14} /> In effect now</div>
        {liveErr ? notice(liveErr, "⚠︎") : live == null ? notice("Checking the National Weather Service…", <div className="spinner" style={{ width: 16, height: 16 }} />)
          : live.length === 0 ? notice("No flood alerts are in effect here right now.", <ShieldCheck size={16} color="var(--green)" />) : live.map(card)}
        <p className="caption">Live from the National Weather Service, which issues flood watches and warnings.</p>
        <div className="section-title"><Clock size={14} /> Past {HISTORY_DAYS} days</div>
        {pastErr ? notice(pastErr, "⚠︎") : past == null ? notice("Checking FEMA's archive…", <div className="spinner" style={{ width: 16, height: 16 }} />)
          : past.length === 0 ? notice("No flood warnings were issued for this spot.", <ShieldCheck size={16} color="var(--muted)" />) : past.map(card)}
        <p className="caption">From FEMA's IPAWS alert archive, which FEMA publishes a day late on purpose — these are history, not current warnings. It lists warnings drawn around this spot; county-wide watches appear only in the live list.</p>
      </div></div>
    </>
  );
}

function AlertDetail({ alert }: { alert: FloodAlert }) {
  const sec = (t: string, body: string) => body ? <><div className="group-head">{t}</div><div className="card small" style={{ whiteSpace: "pre-wrap", userSelect: "text" }}>{body}</div></> : null;
  return (
    <div className="scroll" style={{ paddingTop: 14 }}>
      <div className="card stack" style={{ gap: 8 }}>
        <b style={{ fontSize: 19 }}>{alert.event}</b>
        <span className="chip" style={{ alignSelf: "flex-start", background: (alert.live ? alertColor(alert.severity) : "#8e8e93") + "24", color: alert.live ? alertColor(alert.severity) : "var(--muted)" }}>
          {alert.live ? "In effect now" : "Past alert — not current"}</span>
        <span className="small">{alert.headline}</span>
      </div>
      {sec("Area", alert.area)}{sec("What to do", alert.instruction)}{sec("Details", alert.details)}
      <div className="group-head">Source</div>
      <div className="group">
        <div className="cell"><span>Issued by</span><span className="val">{alert.sender || "—"}</span></div>
        <div className="cell"><span>Source</span><span className="val">{alert.live ? "National Weather Service" : "FEMA IPAWS archive"}</span></div>
      </div>
    </div>
  );
}

export function ShelterScreen() {
  const area = useArea();
  const nav = useNav();
  const [shelters, setShelters] = useState<Shelter[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const load = (p: { latitude: number; longitude: number }) => {
    setShelters(null);
    fetchShelters(p.latitude, p.longitude).then(s => { setShelters(s); setError(null); }).catch(e => { setShelters([]); setError(e.message); });
  };
  useEffect(() => { area.useMine().then(load); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const validZip = /^\d{5}$/.test(area.zip);

  return (
    <>
      <NavBar title="Find a Shelter" />
      <div className="scroll"><div className="stack">
        <AreaBar area={area} onPoint={load} />
        {shelters == null ? <div className="card row small"><div className="spinner" style={{ width: 16, height: 16 }} /> Checking FEMA's open shelter list…</div>
          : error ? <div className="card small" style={{ color: "var(--orange)" }}>⚠︎ {error}</div>
          : shelters.length === 0 ? (
            <div className="card" style={{ textAlign: "center", padding: "18px 14px" }}>
              <House size={34} color="var(--teal)" />
              <h3 style={{ margin: "8px 0 4px" }}>No open shelters nearby</h3>
              <p className="small muted" style={{ margin: 0 }}>FEMA lists no shelters open within {SHELTER_RADIUS_MILES} miles right now. Shelters open when a storm displaces people, so this is normal on a calm day.</p>
            </div>
          ) : shelters.map(s => (
            <div key={s.id} className="card">
              <div className="row" style={{ alignItems: "flex-start" }}>
                <div style={{ flex: 1 }}>
                  <b className="rounded">{s.name}</b>
                  <div className="small muted">{s.address}</div>
                  {s.organization && <div className="tiny muted">Run by {s.organization}</div>}
                </div>
                {s.miles != null && <b className="small" style={{ color: "var(--teal)" }}>{s.miles.toFixed(1)} mi</b>}
              </div>
              <div className="row" style={{ gap: 6, margin: "8px 0" }}>
                <span className="chip" style={{ background: "#34c75924", color: "var(--green)" }}><CircleCheck size={11} /> Open</span>
                {s.pets != null && <span className="chip" style={{ background: "#8e8e9324", color: s.pets ? "var(--teal)" : "var(--muted)" }}><PawPrint size={11} /> {s.pets ? "Pets OK" : "No pets"}</span>}
                {s.accessible && <span className="chip" style={{ background: "#179eb024", color: "var(--teal)" }}><Accessibility size={11} /> Accessible</span>}
              </div>
              {s.latitude != null && <a className="row small" style={{ color: "var(--teal)", fontWeight: 600, gap: 5, textDecoration: "none" }} target="_blank" rel="noreferrer"
                href={`https://maps.apple.com/?daddr=${s.latitude},${s.longitude}&dirflg=d`}><Navigation size={13} /> Directions</a>}
            </div>
          ))}
        <div className="card stack" style={{ gap: 10 }}>
          <b className="row rounded"><MessageSquare size={17} /> Ask FEMA by text</b>
          <span className="small muted">FEMA replies with the nearest open shelters. It works without a data connection.</span>
          <a className={`btn primary ${validZip ? "" : "disabled"}`} style={{ textDecoration: "none", opacity: validZip ? 1 : 0.45, pointerEvents: validZip ? "auto" : "none" }}
             href={`sms:${FEMA_TEXT_NUMBER}&body=SHELTER%20${area.zip}`}
             onClick={e => { if (!canCallAndText()) { e.preventDefault();
               nav.dialog({ title: "Can't send texts from this device", message: `From a phone, text SHELTER ${area.zip} to ${FEMA_TEXT_NUMBER}.`, actions: [{ label: "OK" }] }); } }}>{validZip ? `Text “SHELTER ${area.zip}” to ${FEMA_TEXT_NUMBER}` : "Enter a ZIP code above"}</a>
          <span className="caption" style={{ margin: 0 }}>Opens Messages with the text written; you tap send. Message and data rates may apply.</span>
        </div>
        <p className="caption">In immediate danger, call 911. Follow evacuation orders from local officials — they are the final word on which shelters are open.</p>
      </div></div>
    </>
  );
}
