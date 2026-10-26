import { ChevronRight, House, Radio, RefreshCw, ShieldCheck, TriangleAlert, Waves } from "lucide-react";
import { MapContainer, Marker, TileLayer } from "react-leaflet";
import { Header, useNav } from "../components/ui";
import { relativeTime } from "../lib/models";
import { gaugePin } from "./MapScreen";
import { gaugeAlert, gaugeColor, gaugeLabel, type Station } from "../lib/publicData";
import { useStore } from "../lib/store";
import { FloodAlertsScreen, ShelterScreen } from "./Safety";

function Tank({ s }: { s: Station }) {
  const color = gaugeColor[gaugeAlert(s)];
  const level = s.heightFt == null ? 0.08 : Math.max(0.08, Math.min(s.heightFt / s.floodStageFt, 1));
  return (
    <div style={{ position: "relative", width: 44, height: 58, borderRadius: 12, overflow: "hidden", background: color + "1f", border: `1.5px solid ${color}73`, flexShrink: 0 }}>
      <svg viewBox="0 0 44 58" preserveAspectRatio="none" style={{ position: "absolute", left: 0, bottom: 0, width: "100%", height: `${level * 100 + 8}%` }}>
        <path d="M0 4 Q11 0 22 4 T44 4 V58 H0 Z" fill={color} />
      </svg>
      <div style={{ position: "absolute", top: 6, left: 5, right: 5, height: 1.5, background: "rgba(0,0,0,.35)" }} />
    </div>
  );
}

export function GaugeBar({ s }: { s: Station }) {
  const color = gaugeColor[gaugeAlert(s)];
  const p = s.heightFt == null ? 0 : Math.max(0, Math.min(s.heightFt / s.floodStageFt, 1));
  return (
    <div style={{ position: "relative", height: 10, borderRadius: 5, background: "rgba(120,120,128,.16)" }}>
      <div style={{ width: `${Math.max(3, p * 100)}%`, height: "100%", borderRadius: 5, background: `linear-gradient(90deg, ${color}b3, ${color})` }} />
      <div style={{ position: "absolute", top: -2, height: 14, width: 2, background: "rgba(0,0,0,.35)", left: `${(s.actionStageFt / s.floodStageFt) * 100}%` }} />
    </div>
  );
}

export function RiversScreen() {
  const { stations, gaugesUpdated, gaugesError, refreshGauges, liveAlerts, simulating } = useStore();
  const nav = useNav();

  const tile = (icon: React.ReactNode, title: string, detail: string, colors: [string, string], run: () => void) => (
    <button onClick={run} style={{ flex: 1, minHeight: 120, padding: 14, borderRadius: 16, color: "#fff", textAlign: "left", display: "flex", flexDirection: "column",
      background: `linear-gradient(135deg, ${colors[0]}, ${colors[1]})`, boxShadow: `0 5px 12px ${colors[0]}4d` }}>
      {icon}<span className="spacer" />
      <b className="rounded" style={{ fontSize: 15 }}>{title}</b><span style={{ fontSize: 11, opacity: 0.85 }}>{detail}</span>
    </button>
  );

  return (
    <div className="screen">
      <Header title="Flood Watch" subtitle={`${stations.length} NJ gauges · live from USGS`}
              trailing={<button onClick={refreshGauges} aria-label="Refresh gauges" style={{ color: "#fff" }}><RefreshCw size={24} /></button>} />
      <div className="scroll">
        <div className="stack">
          <div className="row" style={{ gap: 10, alignItems: "stretch" }}>
            {tile(liveAlerts.length ? <TriangleAlert size={26} /> : <ShieldCheck size={26} />, "Flood alerts",
                  liveAlerts.length ? `${liveAlerts.length} in effect now` : "None in effect",
                  liveAlerts.length ? ["#c71c1c", "#ff9500"] : ["#0d2e4f", "#179eb0"], () => nav.push(<FloodAlertsScreen />))}
            {tile(<House size={26} />, "Find a shelter", "FEMA open shelters", ["#4d52c7", "#3d94db"], () => nav.push(<ShelterScreen />))}
          </div>
          <div className="section-title"><Waves size={15} /> River gauges</div>
          <div className="card tight row small" style={{ color: simulating || gaugesError ? "var(--orange)" : "var(--teal)" }}>
            {simulating ? <><TriangleAlert size={14} /> Simulated nor'easter levels, not live USGS data.</>
              : gaugesError ? <>{gaugesError}</>
              : gaugesUpdated ? <><Radio size={14} /> Live gage heights, updated just now.</> : <><div className="spinner" style={{ width: 14, height: 14 }} /> Polling USGS Water Services…</>}
          </div>
          {stations.map(s => {
            const a = gaugeAlert(s), color = gaugeColor[a];
            const below = s.heightFt != null ? s.floodStageFt - s.heightFt : null;
            return (
              <button key={s.siteID} className="card row" style={{ gap: 14, textAlign: "left" }} onClick={() => nav.push(<StationDetail siteID={s.siteID} pushed />)}>
                <Tank s={s} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="row" style={{ alignItems: "flex-start", gap: 8 }}>
                    <div style={{ flex: 1 }}><b className="rounded" style={{ fontSize: 15 }}>{s.name}</b><div className="tiny muted">{s.county} County</div></div>
                    <span className="badge" style={{ background: color + "2e", color }}>{gaugeLabel[a]}</span>
                  </div>
                  <div style={{ margin: "8px 0" }}><GaugeBar s={s} /></div>
                  <div className="row" style={{ gap: 4 }}>
                    {s.heightFt != null ? <><b className="rounded" style={{ color, fontSize: 19 }}>{s.heightFt.toFixed(2)}</b><span className="small" style={{ color, fontWeight: 600 }}>ft</span></>
                      : <span className="small muted">No reading</span>}
                    <span className="spacer" />
                    {below != null && <span className="tiny" style={{ color: below > 0 ? "var(--muted)" : "var(--red)", fontWeight: below > 0 ? 400 : 600 }}>
                      {below > 0 ? `${below.toFixed(1)} ft below flood stage` : "at or above flood stage"}</span>}
                    <ChevronRight size={13} color="var(--faint)" />
                  </div>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

export function StationDetail({ siteID, pushed = false }: { siteID: string; pushed?: boolean }) {
  const { stations } = useStore();
  const nav = useNav();
  const s = stations.find(x => x.siteID === siteID)!;
  const a = gaugeAlert(s);
  const margin = s.heightFt != null ? s.floodStageFt - s.heightFt : null;
  return (
    <>
      {pushed
        ? <div className="navbar"><button className="back" onClick={nav.pop} aria-label="Back">‹</button>Gauge</div>
        : <div style={{ textAlign: "center", fontWeight: 600, padding: "10px 0 6px" }}>Gauge</div>}
      <div className="scroll">
        <div className="card stack">
          <b style={{ fontSize: 17 }}>{s.name}</b>
          <span className="small muted">{s.county} County · USGS {s.siteID}</span>
          <GaugeBar s={s} />
        </div>
        <div className="group-head">Readings</div>
        <div className="group">
          {[["Current gage height", s.heightFt != null ? `${s.heightFt.toFixed(2)} ft` : "—"], ["Action stage", `${s.actionStageFt.toFixed(1)} ft`],
            ["Flood stage", `${s.floodStageFt.toFixed(1)} ft`],
            ...(margin != null ? [[margin >= 0 ? "Below flood stage" : "Above flood stage", `${Math.abs(margin).toFixed(2)} ft`]] : []),
            ["Alert", gaugeLabel[a]], ["Reading time", s.readingTime ? relativeTime(s.readingTime) : "—"]].map(([k, v]) => <div key={k} className="cell"><span>{k}</span><span className="val">{v}</span></div>)}
        </div>
        <div style={{ height: 180, borderRadius: 14, overflow: "hidden", pointerEvents: "none", margin: "16px 0 0" }}>
          <MapContainer center={[s.latitude, s.longitude]} zoom={13} zoomControl={false} style={{ height: "100%" }}>
            <TileLayer url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="&copy; OpenStreetMap" />
            <Marker position={[s.latitude, s.longitude]} icon={gaugePin(gaugeColor[a])} />
          </MapContainer>
        </div>
        <p className="group-foot">Gage height comes from the USGS Water Services instantaneous-values API (parameter 00065). Action and flood thresholds in this build are demo values and must be replaced with official NWS AHPS stages before real use.</p>
      </div>
    </>
  );
}
