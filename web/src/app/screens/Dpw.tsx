import { Building2, ChevronRight, Eye, Share, Sheet, Copy } from "lucide-react";
import { HazardGlyph, Header, SeverityBadge, useNav } from "../components/ui";
import { FEED_URL } from "../lib/config";
import type { Hazard } from "../lib/models";
import { hazardLabel, relativeTime, severityWeight } from "../lib/models";
import { useStore } from "../lib/store";
import { HazardDetail } from "./HazardDetail";

const geoJSON = (hs: Hazard[]) => JSON.stringify({
  type: "FeatureCollection", generated_at: new Date().toISOString(), source: "StormWatch NJ",
  features: hs.map(h => ({ type: "Feature", geometry: { type: "Point", coordinates: [h.longitude, h.latitude] },
    properties: { id: h.id, report_type: h.reportType, severity: h.severity, road_status: h.roadStatus, utility_lines_involved: h.utilityLinesInvolved,
                  description: h.details, municipality: h.municipality, status: h.status, upvotes: h.upvotes, created_at: h.createdAt } })),
}, null, 2);

const csv = (hs: Hazard[]) => {
  const esc = (v: string) => /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
  return ["id,report_type,severity,road_status,utility_lines_involved,municipality,status,upvotes,latitude,longitude,created_at,description",
    ...hs.map(h => [h.id, h.reportType, h.severity, h.roadStatus, h.utilityLinesInvolved, esc(h.municipality), h.status, h.upvotes,
                    h.latitude.toFixed(6), h.longitude.toFixed(6), h.createdAt, esc(h.details)].join(","))].join("\n");
};

function download(name: string, text: string, type: string) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  Object.assign(document.createElement("a"), { href: url, download: name }).click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Township staff only. Hiding the tab is a convenience; the server enforces what staff may do. */
export function DpwScreen() {
  const { hazards, account } = useStore();
  const nav = useNav();
  const open = hazards.filter(h => h.status !== "RESOLVED")
    .sort((a, b) => severityWeight[b.severity] - severityWeight[a.severity] || b.updatedAt.localeCompare(a.updatedAt));

  return (
    <div className="screen">
      <Header title="DPW Console" subtitle={`${account?.township ?? "Township"} · ${open.length} open work orders`} trailing={<Building2 size={26} />} />
      <div className="scroll">
        <div className="group-head" style={{ marginTop: 4 }}>Open dispatch queue</div>
        <div className="group">
          {open.length === 0 ? <div className="cell muted">No open work orders.</div> : open.map(h => (
            <button key={h.id} className="cell" onClick={() => nav.push(<HazardDetail hazardId={h.id} pushed />)}>
              <HazardGlyph type={h.reportType} size={36} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 500 }}>{hazardLabel[h.reportType]}</div>
                <div className="tiny muted">{h.municipality} · {relativeTime(h.createdAt)}</div>
              </div>
              <SeverityBadge severity={h.severity} /><ChevronRight size={15} color="var(--faint)" />
            </button>
          ))}
        </div>
        <p className="group-foot">Sorted by severity, then most recently updated — the order a crew would work it.</p>

        <div className="group-head">Municipal export</div>
        <div className="group">
          <button className="cell link" onClick={() => download("stormwatch_nj_hazards.geojson", geoJSON(open), "application/geo+json")}><Share size={18} /> Export GeoJSON</button>
          <button className="cell link" onClick={() => download("stormwatch_nj_hazards.csv", csv(open), "text/csv")}><Sheet size={18} /> Export CSV</button>
          <button className="cell link" onClick={() => nav.present(
            <div className="scroll"><pre style={{ fontSize: 10.5, whiteSpace: "pre-wrap", userSelect: "text" }}>{geoJSON(open)}</pre></div>)}><Eye size={18} /> Preview GeoJSON</button>
        </div>
        <p className="group-foot">RFC 7946 FeatureCollection with longitude-first coordinates, ready for ArcGIS, QGIS or a routing tool.</p>

        <div className="group-head">Public works relay</div>
        <div className="group">
          <div className="cell" style={{ flexDirection: "column", alignItems: "flex-start", gap: 4 }}>
            <span className="tiny muted">Live GIS feed</span>
            <code style={{ fontSize: 11, wordBreak: "break-all", userSelect: "text" }}>{FEED_URL}</code>
          </div>
          <button className="cell link" onClick={() => navigator.clipboard?.writeText(FEED_URL)}><Copy size={18} /> Copy feed link</button>
        </div>
        <p className="group-foot">Every report is filed over the Open311 civic standard, and towns that have opted in receive it at their public works desk. The feed link can be added to ArcGIS Online or QGIS as a live layer. Photos are never sent.</p>
      </div>
    </div>
  );
}
