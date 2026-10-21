import { useState } from "react";
import { LayoutGrid, List, LocateFixed, ShieldCheck } from "lucide-react";
import { HazardCard, Header, hazardIcon, useNav } from "../components/ui";
import type { HazardType } from "../lib/models";
import { HAZARD_TYPES, hazardShort, milesBetween } from "../lib/models";
import { useStore } from "../lib/store";
import { HazardDetail } from "./HazardDetail";

export function NearbyScreen() {
  const { nearby, location, locationText, settings } = useStore();
  const nav = useNav();
  const [filter, setFilter] = useState<HazardType | null>(null);
  const list = nearby().filter(h => !filter || h.reportType === filter);

  const chip = (label: string, icon: React.ReactNode, on: boolean, run: () => void) => (
    <button key={label} onClick={run} className="row" style={{ gap: 5, padding: "8px 12px", borderRadius: 99, fontSize: 13, fontWeight: 600, whiteSpace: "nowrap",
      background: on ? "var(--teal)" : "var(--card)", color: on ? "#fff" : "var(--text)" }}>{icon}{label}</button>
  );

  return (
    <div className="screen">
      <Header title="Nearby Hazards" subtitle={`${list.length} active within ${settings.radiusMiles} miles`} trailing={<List size={26} />} />
      <div className="row" style={{ gap: 8, overflowX: "auto", padding: "8px 16px", flexShrink: 0, scrollbarWidth: "none" }}>
        {chip("All", <LayoutGrid size={12} />, !filter, () => setFilter(null))}
        {HAZARD_TYPES.map(t => chip(hazardShort[t], hazardIcon(t, 12), filter === t, () => setFilter(filter === t ? null : t)))}
      </div>
      <div className="scroll" style={{ paddingTop: 4 }}>
        {list.length === 0 ? (
          <div style={{ textAlign: "center", padding: "50px 20px" }}>
            <ShieldCheck size={40} color="var(--teal)" />
            <h3 style={{ margin: "10px 0 4px" }}>{filter ? "Nothing of that type nearby" : "No active hazards nearby"}</h3>
            <p className="small muted">{filter ? "Try another filter or widen the search radius." : `Nothing reported within ${settings.radiusMiles} miles. Widen the radius in Settings, or be the first to report one.`}</p>
          </div>
        ) : (
          <div className="stack">
            {list.map(h => <HazardCard key={h.id} hazard={h} miles={milesBetween(location, h)} onClick={() => nav.push(<HazardDetail hazardId={h.id} pushed />)} />)}
          </div>
        )}
        <p className="row tiny muted" style={{ marginTop: 14, gap: 6 }}><LocateFixed size={12} /> {locationText}</p>
      </div>
    </div>
  );
}
