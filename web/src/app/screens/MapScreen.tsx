import { useEffect, useMemo, useState } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MapContainer, Marker, TileLayer, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { ChevronRight, Droplet, LocateFixed, Navigation, OctagonX, TriangleAlert, Waves, Zap } from "lucide-react";
import { HazardGlyph, SeverityBadge, hazardIcon, useNav } from "../components/ui";
import type { Hazard } from "../lib/models";
import { hazardLabel, milesBetween, severityColor } from "../lib/models";
import { alertColor, gaugeAlert, gaugeColor } from "../lib/publicData";
import { useStore } from "../lib/store";
import { FloodAlertsScreen } from "./Safety";
import { HazardDetail } from "./HazardDetail";
import { StationDetail } from "./Rivers";

const html = (node: React.ReactElement) => renderToStaticMarkup(node);

function hazardPin(h: Hazard) {
  const size = 32, c = severityColor[h.severity];
  const pin = `<div class="pin" style="width:${size}px;height:${size}px;background:${c}">${html(hazardIcon(h.reportType, 15))}</div>`;
  const halo = h.severity === "IMPASSABLE";
  const outer = halo ? 56 : size;
  return L.divIcon({
    className: "", iconSize: [outer, outer], iconAnchor: [outer / 2, outer / 2],
    html: halo ? `<div class="pin-halo" style="width:${outer}px;height:${outer}px;background:${c}38">${pin}</div>` : pin,
  });
}

export function gaugePin(color: string) {
  return L.divIcon({ className: "", iconSize: [28, 28], iconAnchor: [14, 14],
    html: `<div class="gpin" style="background:${color}">${html(<Waves size={14} strokeWidth={2.6} />)}</div>` });
}

const meIcon = L.divIcon({ className: "", iconSize: [18, 18], iconAnchor: [9, 9], html: `<div class="me-dot"></div>` });

function Recenter({ to, tick }: { to: [number, number]; tick: number }) {
  const map = useMap();
  useEffect(() => { map.flyTo(to, 11, { duration: 0.6 }); }, [tick]); // eslint-disable-line react-hooks/exhaustive-deps
  return null;
}

export function MapScreen() {
  const { nearby, stations, location, locationMode, locationText, liveAlerts, simulating } = useStore();
  const nav = useNav();
  const [showGauges, setShowGauges] = useState(true);
  const [tick, setTick] = useState(0);
  const visible = nearby();
  const worst = useMemo(() => [...visible].sort((a, b) => ({ LOW: 0, MODERATE: 1, IMPASSABLE: 2 }[b.severity] - { LOW: 0, MODERATE: 1, IMPASSABLE: 2 }[a.severity]))[0], [visible]);
  const rising = stations.filter(s => gaugeAlert(s) !== "NORMAL").length;
  const open = (h: Hazard) => nav.present(<HazardDetail hazardId={h.id} />);

  const stat = (icon: React.ReactNode, value: number, label: string, color: string) => (
    <div style={{ flex: 1, textAlign: "center" }}>
      <div className="row rounded" style={{ justifyContent: "center", gap: 4, color, fontWeight: 700, fontSize: 19 }}>{icon}{value}</div>
      <div className="tiny muted">{label}</div>
    </div>
  );

  return (
    <div className="screen">
      <MapContainer center={[location.latitude, location.longitude]} zoom={11} zoomControl={false} attributionControl
                    className="map-main" style={{ position: "absolute", inset: 0 }}>
        <TileLayer url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
                   attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>' />
        <Recenter to={[location.latitude, location.longitude]} tick={tick} />
        {locationMode === "live" && <Marker position={[location.latitude, location.longitude]} icon={meIcon} />}
        {showGauges && stations.map(s => (
          <Marker key={s.siteID} position={[s.latitude, s.longitude]} icon={gaugePin(gaugeColor[gaugeAlert(s)])}
                  eventHandlers={{ click: () => nav.present(<StationDetail siteID={s.siteID} />) }} />
        ))}
        {visible.map(h => (
          <Marker key={h.id} position={[h.latitude, h.longitude]} icon={hazardPin(h)} eventHandlers={{ click: () => open(h) }} />
        ))}
      </MapContainer>

      <div style={{ position: "absolute", top: 54, left: 0, right: 0, zIndex: 500, textAlign: "center", fontWeight: 600, fontSize: 17, pointerEvents: "none" }}>StormWatch NJ</div>
      <button onClick={() => setTick(t => t + 1)} aria-label="Recenter map" className="glass"
              style={{ position: "absolute", top: 46, right: 16, zIndex: 500, width: 44, height: 44, borderRadius: 22, display: "grid", placeItems: "center", color: "var(--teal)", boxShadow: "0 2px 8px rgba(0,0,0,.12)" }}>
        <LocateFixed size={22} />
      </button>

      <div style={{ position: "absolute", top: 100, left: 14, right: 14, zIndex: 500, display: "flex", flexDirection: "column", gap: 8 }}>
        <div className="glass row" style={{ padding: "10px 6px", borderRadius: 14, boxShadow: "0 3px 10px rgba(0,0,0,.12)" }}>
          {stat(<OctagonX size={15} />, visible.filter(h => h.severity === "IMPASSABLE").length, "impassable", "var(--red)")}
          {stat(<Zap size={15} />, visible.filter(h => h.utilityLinesInvolved).length, "wires down", "var(--orange)")}
          {stat(<Waves size={15} />, rising, "rivers rising", "var(--teal)")}
          <button onClick={() => setShowGauges(!showGauges)} style={{ flex: 1, color: showGauges ? "var(--teal)" : "var(--muted)" }}>
            <Droplet size={18} fill={showGauges ? "currentColor" : "none"} /><div className="tiny">gauges</div>
          </button>
        </div>
        {liveAlerts[0] && (
          <button className="row" onClick={() => nav.push(<FloodAlertsScreen />)}
                  style={{ padding: "10px 12px", borderRadius: 99, background: alertColor(liveAlerts[0].severity), color: ["Severe", "Extreme", "Moderate"].includes(liveAlerts[0].severity) ? "#fff" : "#000", fontWeight: 700, fontSize: 12 }}>
            <TriangleAlert size={14} /> {liveAlerts[0].event}{liveAlerts.length > 1 ? ` and ${liveAlerts.length - 1} more` : ""} in effect <span className="spacer" /><ChevronRight size={14} />
          </button>
        )}
        {locationMode !== "live" && (
          <div className="glass row small" style={{ padding: "9px 12px", borderRadius: 99, fontWeight: 500, fontSize: 11.5 }}>
            <Navigation size={12} /> {locationText}
          </div>
        )}
        {simulating && (
          <div className="row" style={{ justifyContent: "center", padding: "9px 12px", borderRadius: 99, background: "var(--orange)", color: "#fff", fontWeight: 700, fontSize: 11.5 }}>
            <TriangleAlert size={13} /> Simulated nor'easter — this data is not real
          </div>
        )}
      </div>

      {worst && (
        <button className="glass row" onClick={() => open(worst)}
                style={{ position: "absolute", left: 14, right: 14, bottom: 98, zIndex: 500, padding: 12, borderRadius: 14, gap: 11, textAlign: "left", boxShadow: "0 4px 14px rgba(0,0,0,.15)" }}>
          <HazardGlyph type={worst.reportType} size={42} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="row" style={{ gap: 6 }}><b className="rounded">{hazardLabel[worst.reportType]}</b><SeverityBadge severity={worst.severity} /></div>
            <div className="tiny muted">{milesBetween(location, worst).toFixed(1)} mi away · {worst.municipality}</div>
          </div>
          <ChevronRight size={16} color="var(--faint)" />
        </button>
      )}
    </div>
  );
}
