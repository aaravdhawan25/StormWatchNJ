import { useEffect, useState } from "react";
import { Building2, Camera, Landmark, Waves } from "lucide-react";
import { AppLogo, StormBackdrop } from "../components/ui";
import { useStore } from "../lib/store";
import { AuthScreen } from "./Auth";

type Route = { kind: "resident" | "township"; creating: boolean } | null;

export function WelcomeScreen() {
  const { enterGuest } = useStore();
  const [route, setRoute] = useState<Route>(null);
  const [shown, setShown] = useState(false);
  useEffect(() => { const t = setTimeout(() => setShown(true), 30); return () => clearTimeout(t); }, []);

  if (route) return <AuthScreen kind={route.kind} creating={route.creating} onBack={() => setRoute(null)} />;

  const feature = (icon: React.ReactNode, title: string, detail: string) => (
    <div className="row" style={{ gap: 14, maxWidth: 300 }}>
      <div style={{ width: 42, height: 42, borderRadius: 12, background: "rgba(255,255,255,.12)", display: "grid", placeItems: "center", color: "var(--amber)" }}>{icon}</div>
      <div>
        <div className="rounded" style={{ fontWeight: 700, fontSize: 15 }}>{title}</div>
        <div style={{ fontSize: 12, opacity: 0.72 }}>{detail}</div>
      </div>
    </div>
  );

  return (
    <div className="screen" style={{ color: "#fff" }}>
      <StormBackdrop />
      <div style={{ position: "relative", flex: 1, display: "flex", flexDirection: "column", alignItems: "center", padding: "70px 28px 36px" }}>
        <div style={{ flex: 1 }} />
        <div style={{ transition: "all .8s cubic-bezier(.3,1.4,.5,1)", transform: shown ? "scale(1)" : "scale(.8)", opacity: shown ? 1 : 0 }}>
          <AppLogo size={104} />
        </div>
        <div className="rounded" style={{ fontSize: 36, fontWeight: 800, marginTop: 18 }}>StormWatch NJ</div>
        <div className="rounded" style={{ fontSize: 15, fontWeight: 500, opacity: 0.8, marginTop: 4 }}>Your neighborhood's storm hazard map</div>
        <div className="stack" style={{ gap: 12, marginTop: 28, alignSelf: "center", transition: "all .8s .1s", opacity: shown ? 1 : 0, transform: shown ? "none" : "translateY(16px)" }}>
          {feature(<Camera size={20} />, "Snap a hazard", "AI fills in the report for you")}
          {feature(<Waves size={20} />, "Watch the rivers", "Live USGS gauges across New Jersey")}
          {feature(<Building2 size={20} />, "Reach public works", "Reports go straight to your town")}
        </div>
        <div style={{ flex: 1 }} />
        <div className="stack" style={{ width: "100%", gap: 11 }}>
          <button className="rounded" onClick={() => setRoute({ kind: "resident", creating: true })}
                  style={{ padding: 15, borderRadius: 99, background: "#fff", color: "var(--navy)", fontWeight: 700, fontSize: 16 }}>Create an account</button>
          <button className="rounded" onClick={() => setRoute({ kind: "resident", creating: false })}
                  style={{ padding: 15, borderRadius: 99, background: "rgba(10,26,51,.55)", border: "1px solid rgba(255,255,255,.55)", color: "#fff", fontWeight: 700, fontSize: 16 }}>Sign in</button>
          <button className="rounded row" onClick={() => setRoute({ kind: "township", creating: false })}
                  style={{ justifyContent: "center", padding: 6, color: "var(--navy)", fontWeight: 700 }}><Landmark size={16} /> Sign in as a township</button>
          <button onClick={enterGuest} style={{ fontSize: 12, fontWeight: 600, color: "var(--navy)", opacity: 0.85, textDecoration: "underline" }}>
            Try the demo without an account
          </button>
        </div>
      </div>
    </div>
  );
}
