import { useState } from "react";
import { ChevronDown, Phone, Zap } from "lucide-react";
import { useNav } from "./ui";
import { canCallAndText } from "../lib/device";

// phone numbers from NJ OEM and PSE&G
const UTILITIES = [
  { name: "JCP&L", phone: "1-888-544-4877" },
  { name: "Atlantic City Electric", phone: "1-800-833-7476" },
  { name: "Orange & Rockland", phone: "1-877-434-4100" },
];
const tel = (n: string) => `tel:${n.replace(/\D/g, "")}`;

// the red alert for any hazard involving utility lines
export function LifeSafetyBanner({ location }: { location?: string }) {
  const [more, setMore] = useState(false);
  const nav = useNav();
  // as in the app: a device that can't place calls says which number to dial
  const call = (label: string, number: string) => (e: React.MouseEvent) => {
    if (canCallAndText()) return;
    e.preventDefault();
    nav.dialog({ title: "Can't place a call from this device", message: `Dial ${number} for ${label}.`, actions: [{ label: "OK" }] });
  };
  return (
    <div className="danger-banner">
      <div className="row" style={{ alignItems: "flex-start" }}>
        <Zap size={26} fill="#fff" style={{ flexShrink: 0 }} />
        <div>
          <div style={{ fontWeight: 800, fontSize: 15 }}>Immediate life-safety risk</div>
          <div style={{ fontSize: 12.5, opacity: 0.95 }}>Do not approach. Stay at least 30 feet back and treat every wire as live.</div>
        </div>
      </div>
      {location && <div style={{ margin: "10px 0 0", padding: "7px 10px", borderRadius: 8, background: "rgba(255,255,255,.16)", fontSize: 12.5, fontWeight: 600, userSelect: "text" }}>
        Tell the dispatcher: {location}</div>}
      <div className="row" style={{ marginTop: 10, gap: 8 }}>
        <a href="tel:911" onClick={call("emergency services", "911")} className="row" style={{ flex: 1, justifyContent: "center", padding: 10, borderRadius: 10, background: "#fff", color: "#c71c1c", fontWeight: 800, fontSize: 14 }}>
          <Phone size={14} fill="currentColor" /> Call 911</a>
        <a href={tel("1-800-436-7734")} onClick={call("PSE&G", "1-800-436-7734")} className="row" style={{ flex: 1, justifyContent: "center", padding: 10, borderRadius: 10, background: "rgba(255,255,255,.18)", color: "#fff", fontWeight: 800, fontSize: 14 }}>
          <Phone size={14} fill="currentColor" /> Call PSE&amp;G</a>
      </div>
      <button className="row" onClick={() => setMore(!more)} style={{ marginTop: 9, color: "#fff", fontSize: 12, fontWeight: 700, gap: 4 }}>
        <ChevronDown size={13} /> Not a PSE&amp;G area? Other NJ utilities
      </button>
      {more && UTILITIES.map(u => (
        <a key={u.name} href={tel(u.phone)} onClick={call(u.name, u.phone)} style={{ display: "block", color: "#fff", fontSize: 12.5, padding: "4px 0 0 18px" }}>{u.name} · {u.phone}</a>
      ))}
    </div>
  );
}
