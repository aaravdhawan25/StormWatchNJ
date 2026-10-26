import { useEffect, useState } from "react";
import { AppRoot } from "./app/AppRoot";
import { StoreProvider } from "./app/lib/store";
import "./page.css";

const PHONE_W = 402, PHONE_H = 874;

function useClock() {
  const [now, setNow] = useState(new Date());
  useEffect(() => { const t = setInterval(() => setNow(new Date()), 15000); return () => clearInterval(t); }, []);
  return now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M/i, "");
}

// on a phone the app fills the screen
export function Page() {
  const [phoneSized, setPhoneSized] = useState(() => window.innerWidth < 600);
  const [scale, setScale] = useState(1);
  const time = useClock();
  useEffect(() => {
    const fit = () => {
      setPhoneSized(window.innerWidth < 600);
      setScale(Math.min(1, (window.innerHeight - 48) / (PHONE_H + 24)));
    };
    fit(); window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);

  if (phoneSized) return <div className="fullscreen"><StoreProvider><AppRoot /></StoreProvider></div>;

  return (
    <div className="page">
      <aside className="intro">
        <img src="/app-icon.png" alt="" width={72} height={72} className="intro-icon" />
        <h1>StormWatch NJ</h1>
        <p className="lede">A neighbor-powered storm hazard map for New Jersey. Snap a flooded road or a downed tree, let AI fill in the report, and it lands on a shared map and at your town's public works desk.</p>
        <ul>
          <li><b>AI photo triage</b> — OpenAI reads the scene and flags downed wires.</li>
          <li><b>Live federal data</b> — USGS river gauges, National Weather Service and FEMA flood alerts, FEMA open shelters.</li>
          <li><b>Built for towns</b> — Open311 reports and a GeoJSON feed for ArcGIS and QGIS.</li>
          <li><b>Community moderation</b> — three neighbors saying "it's gone" takes a hazard off the map.</li>
        </ul>
        <p className="note">This is the web version of the iPhone app, running the same backend and live data. Try it without an account, or create one. Sample hazards are fictional.</p>
      </aside>
      <div className="phone-wrap" style={{ width: (PHONE_W + 24) * scale, height: (PHONE_H + 24) * scale }}>
        <div className="phone" style={{ transform: `scale(${scale})` }}>
          <div className="screen-area">
            <StoreProvider><AppRoot /></StoreProvider>
            <div className="statusbar"><span>{time}</span><span className="island" /><span className="icons">
              <svg width="17" height="11" viewBox="0 0 17 11"><path fill="currentColor" d="M1 7h2v4H1zM5 5h2v6H5zM9 3h2v8H9zM13 0h2v11h-2z"/></svg>
              <svg width="25" height="12" viewBox="0 0 25 12"><rect x=".5" y=".5" width="21" height="11" rx="3.5" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="18" height="8" rx="2" fill="currentColor"/><path d="M23 4v4c.8-.3 1.3-1 1.3-2s-.5-1.7-1.3-2z" fill="currentColor" opacity=".4"/></svg>
            </span></div>
            <div className="home-indicator" />
          </div>
        </div>
      </div>
    </div>
  );
}
