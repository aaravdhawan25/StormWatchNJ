import { useEffect, useState } from "react";
import { Building2, Camera, List, Map, Settings, ShieldAlert } from "lucide-react";
import { NavHost } from "./components/ui";
import { useStore } from "./lib/store";
import { MapScreen } from "./screens/MapScreen";
import { NearbyScreen } from "./screens/Nearby";
import { ReportScreen } from "./screens/Report";
import { RiversScreen } from "./screens/Rivers";
import { SettingsScreen } from "./screens/Settings";
import { DpwScreen } from "./screens/Dpw";
import { WelcomeScreen } from "./screens/Welcome";
import { EmailLinkScreen } from "./screens/EmailLink";
import { emailLink } from "./lib/config";
import "./app.css";

type Tab = "map" | "nearby" | "dpw" | "report" | "alerts" | "settings";

// the app itself: welcome until signed in, then five tabs, the same as the iPhone app
export function AppRoot() {
  const { account, authReady } = useStore();
  const [tab, setTab] = useState<Tab>("map");
  const [link, setLink] = useState(emailLink);
  const township = account?.role === "township";

  // township staff get the DPW console in place of Nearby, as on iPhone
  useEffect(() => {
    if (township && tab === "nearby") setTab("dpw");
    if (!township && tab === "dpw") setTab("nearby");
  }, [township]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (!account) setTab("map"); }, [account]);

  // a tapped notification says which tab to open
  useEffect(() => {
    const open = (target?: string) => {
      if (target === "alerts") setTab("alerts");
      if (target === "nearby") setTab(township ? "dpw" : "nearby");
    };
    const onWindow = (e: Event) => open((e as CustomEvent).detail);
    const onWorker = (e: MessageEvent) => { if (e.data?.type === "open-tab") open(e.data.tab); };
    window.addEventListener("stormwatch-open-tab", onWindow);
    navigator.serviceWorker?.addEventListener("message", onWorker);
    return () => { window.removeEventListener("stormwatch-open-tab", onWindow); navigator.serviceWorker?.removeEventListener("message", onWorker); };
  }, [township]);

  if (!authReady) return <div className="sw" />;
  if (link) return <div className="sw"><EmailLinkScreen {...link} signedIn={!!account && !account.guest} onDone={() => setLink(null)} /></div>;
  if (!account) return <div className="sw"><WelcomeScreen /></div>;

  const tabs: [Tab, string, React.ReactNode][] = [
    ["map", "Map", <Map size={22} />],
    township ? ["dpw", "DPW", <Building2 size={22} />] : ["nearby", "Nearby", <List size={22} />],
    ["report", "Report", <Camera size={22} />],
    ["alerts", "Alerts", <ShieldAlert size={22} />],
    ["settings", "Settings", <Settings size={22} />],
  ];

  return (
    <div className="sw">
      <NavHost resetKey={tab}>
        {tab === "map" && <MapScreen />}
        {tab === "nearby" && <NearbyScreen />}
        {tab === "dpw" && <DpwScreen />}
        {tab === "report" && <ReportScreen />}
        {tab === "alerts" && <RiversScreen />}
        {tab === "settings" && <SettingsScreen />}
        <nav className="tabbar">
          {tabs.map(([id, label, icon]) => (
            <button key={id} className={`tab ${tab === id ? "on" : ""}`} onClick={() => setTab(id)}>{icon}{label}</button>
          ))}
        </nav>
      </NavHost>
    </div>
  );
}
