import { useRef, useState } from "react";
import { Camera, ChevronRight, RotateCcw, Send, Sparkles, BadgeCheck, Wand2, Waves, Leaf, Zap } from "lucide-react";
import { HazardGlyph, Header, StormBackdrop, Toggle, useNav } from "../components/ui";
import { LifeSafetyBanner } from "../components/LifeSafety";
import type { HazardType, RoadStatus, Severity } from "../lib/models";
import { HAZARD_TYPES, ROAD_STATUSES, SEVERITIES, hazardLabel, isLifeSafetyRisk, roadLabel, severityColor, severityLabel } from "../lib/models";
import { useStore, townFor } from "../lib/store";
import { supabase } from "../lib/config";
import { analyzeOnDevice, analyzeWithOpenAI, type Analysis } from "../lib/triage";
import { nextdoorURL } from "./HazardDetail";

export function ReportScreen() {
  const store = useStore();
  const nav = useNav();
  const fileRef = useRef<HTMLInputElement>(null);
  const [photo, setPhoto] = useState<{ blob: Blob; url: string } | null>(null);
  const [analysis, setAnalysis] = useState<Analysis | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [type, setType] = useState<HazardType>("STREET_FLOODING");
  const [severity, setSeverity] = useState<Severity>("MODERATE");
  const [road, setRoad] = useState<RoadStatus>("ONE_LANE_OPEN");
  const [wires, setWires] = useState(false);
  const [details, setDetails] = useState("");
  const [posting, setPosting] = useState(false);
  const town = townFor(store.location);
  const guest = store.account?.guest;

  const reset = () => { setPhoto(null); setAnalysis(null); setError(null); setDetails(""); setWires(false); setSeverity("MODERATE"); setRoad("ONE_LANE_OPEN"); setType("STREET_FLOODING"); };

  const apply = (a: Analysis) => { setAnalysis(a); setType(a.hazardType); setSeverity(a.severity); setRoad(a.roadStatus); setWires(a.utilityLines); setDetails(a.description); };

  const triage = async (blob: Blob) => {
    setAnalyzing(true); setError(null); setAnalysis(null);
    try {
      const token = (await supabase.auth.getSession()).data.session?.access_token;
      if (!token) { apply(await analyzeOnDevice(blob, town)); return; }
      try { apply(await analyzeWithOpenAI(blob, token)); }
      catch (e) { setError(`${(e as Error).message} Used on-device analysis instead.`); apply(await analyzeOnDevice(blob, town)); }
    } finally { setAnalyzing(false); }
  };

  const take = (blob: Blob) => { const url = URL.createObjectURL(blob); setPhoto({ blob, url }); triage(blob); };
  const useDemo = async (file: string) => take(await (await fetch(file)).blob());

  const post = async () => {
    setPosting(true);
    try {
      const h = await store.report({ reportType: type, severity, roadStatus: road, utilityLinesInvolved: wires, details: details.trim(),
        latitude: store.location.latitude, longitude: store.location.longitude, municipality: town, photoURL: photo?.url });
      reset();
      const actions = [{ label: "Done" }];
      nav.dialog({
        title: "Report submitted",
        message: (guest ? "Your report is on the map in this browser. Create an account to share reports with your neighbors and town."
                        : "Your report is on the map and in the public works queue.")
          + (store.settings.offerNextdoor ? " Want to tell your neighborhood too? Nextdoor will open with the post written for you — you review it and tap Post there." : ""),
        actions: store.settings.offerNextdoor ? [{ label: "Share to Nextdoor", strong: true, run: () => window.open(nextdoorURL(h), "_blank") }, ...actions] : actions,
      });
    } catch (e) {
      nav.dialog({ title: "Couldn't post", message: (e as Error).message, actions: [{ label: "OK" }] });
    } finally { setPosting(false); }
  };

  const showSafety = photo && isLifeSafetyRisk(type, wires);

  return (
    <div className="screen">
      <Header title="Snap & Triage" subtitle={photo ? "Check the details, then post" : "Photograph a hazard to begin"}
              trailing={photo && <button onClick={reset} aria-label="Start over" style={{ color: "#fff" }}><RotateCcw size={24} /></button>} />
      {showSafety && <div style={{ marginTop: -10, zIndex: 2 }}><LifeSafetyBanner location={`${town}, NJ`} /></div>}
      <input ref={fileRef} type="file" accept="image/*" capture="environment" hidden onChange={e => { const f = e.target.files?.[0]; if (f) take(f); e.target.value = ""; }} />
      <div className="scroll">
        {!photo ? (
          <div className="stack" style={{ gap: 14 }}>
            <div style={{ borderRadius: 16, overflow: "hidden", background: "var(--card)", boxShadow: "0 5px 12px rgba(0,0,0,.08)" }}>
              <div style={{ position: "relative", height: 170, color: "#fff", display: "grid", placeItems: "center" }}>
                <StormBackdrop waterLevel={0.34} animated={false} />
                <div style={{ position: "relative", textAlign: "center", paddingBottom: 24 }}>
                  <Camera size={44} style={{ filter: "drop-shadow(0 0 10px var(--bright))" }} />
                  <div className="rounded" style={{ fontWeight: 700, fontSize: 19, marginTop: 6 }}>Report a storm hazard</div>
                </div>
              </div>
              <div className="row" style={{ padding: "14px 8px" }}>
                {[[<Camera size={18} key="c" />, "Snap"], [<Sparkles size={18} key="s" />, "AI fills it in"], [<BadgeCheck size={18} key="b" />, "You confirm"]].map(([icon, label], i) => (
                  <div key={i} className="row" style={{ flex: 1, gap: 0 }}>
                    <div style={{ flex: 1, textAlign: "center", color: "var(--teal)" }}>{icon}<div className="tiny muted" style={{ fontWeight: 600 }}>{label}</div></div>
                    {i < 2 && <ChevronRight size={12} color="var(--faint)" />}
                  </div>
                ))}
              </div>
            </div>
            <button className="btn primary" onClick={() => fileRef.current?.click()}><Camera size={18} /> Take or choose a photo</button>
            <div className="card">
              <div className="row small muted" style={{ fontWeight: 600, marginBottom: 10 }}><Wand2 size={14} /> Try it with a sample scene</div>
              <div className="row" style={{ gap: 10 }}>
                {([["/demo-flooded-road.jpg", "Flooded road", <Waves size={20} key="w" />, "STREET_FLOODING"], ["/demo-downed-tree.jpg", "Tree across road", <Leaf size={20} key="l" />, "DOWNED_TREE"]] as const).map(([file, label, icon, t]) => (
                  <button key={file} onClick={() => useDemo(file)} style={{ flex: 1, padding: "12px 0", borderRadius: 14, color: "#fff", fontSize: 12, fontWeight: 600,
                          background: t === "STREET_FLOODING" ? "linear-gradient(135deg,#1f73db,#24b8d6)" : "linear-gradient(135deg,#1a8052,#6bb84d)" }}>
                    {icon}<div>{label}</div>
                  </button>
                ))}
              </div>
              <p className="caption" style={{ margin: "10px 0 0" }}>Illustrations, not photographs — they exist so the triage engine can be tested without a camera roll.</p>
            </div>
            {guest && <p className="caption">Guest demo: photos are analyzed in the browser. Sign in to use OpenAI analysis.</p>}
          </div>
        ) : (
          <div className="stack" style={{ gap: 14 }}>
            <div style={{ position: "relative" }}>
              <img src={photo.url} alt="" style={{ width: "100%", height: 210, objectFit: "cover", borderRadius: 16, display: "block" }} />
              <button onClick={reset} className="row glass" style={{ position: "absolute", right: 10, bottom: 10, padding: "7px 10px", borderRadius: 99, fontSize: 12, fontWeight: 600, gap: 4 }}>
                <RotateCcw size={13} /> Retake</button>
            </div>
            <div className="card">
              <div className="row" style={{ gap: 12 }}>
                {analyzing ? <div style={{ width: 58, height: 58, display: "grid", placeItems: "center" }}><div className="spinner" /></div>
                  : analysis?.confidence != null ? <Ring value={analysis.confidence} color={severityColor[analysis.severity]} />
                  : analysis ? <HazardGlyph type={analysis.hazardType} size={58} />
                  : <Sparkles size={30} color="var(--teal)" style={{ width: 58 }} />}
                <div>
                  <b style={{ fontSize: 17 }}>{analyzing ? "Analyzing scene…" : analysis ? hazardLabel[analysis.hazardType] : "Not analyzed yet"}</b>
                  <div className="small" style={{ color: "var(--teal)" }}>{analysis?.engine ?? (guest ? "On-device analysis" : "OpenAI vision")}</div>
                </div>
              </div>
              {analysis && <div style={{ marginTop: 12 }}>
                <div className="small muted" style={{ fontWeight: 600, marginBottom: 4 }}>What the engine saw</div>
                {analysis.evidence.map(e => <div key={e} className="tiny muted" style={{ padding: "2px 0" }}>• {e}</div>)}
              </div>}
              {error && <div className="tiny" style={{ color: "var(--orange)", marginTop: 8 }}>⚠︎ {error}</div>}
              <p className="caption" style={{ margin: "10px 0 0" }}>These fields were machine-filled. Check them before you post.</p>
            </div>

            <div className="card stack" style={{ gap: 14 }}>
              <b style={{ fontSize: 17 }}>Confirm the report</b>
              <Field label="Hazard">
                <select value={type} onChange={e => setType(e.target.value as HazardType)} style={{ border: 0, background: "none", color: "var(--teal)", fontSize: 17, padding: 0 }}>
                  {HAZARD_TYPES.map(t => <option key={t} value={t}>{hazardLabel[t]}</option>)}
                </select>
              </Field>
              <Field label="Severity">
                <div className="row" style={{ background: "rgba(118,118,128,.12)", borderRadius: 9, padding: 2, gap: 2 }}>
                  {SEVERITIES.map(s => <button key={s} onClick={() => setSeverity(s)} style={{ flex: 1, padding: "6px 0", borderRadius: 7, fontSize: 13, fontWeight: 500,
                    background: severity === s ? "#fff" : "none", boxShadow: severity === s ? "0 2px 5px rgba(0,0,0,.12)" : "none" }}>{severityLabel[s]}</button>)}
                </div>
              </Field>
              <Field label="Road">
                <select value={road} onChange={e => setRoad(e.target.value as RoadStatus)} style={{ border: 0, background: "none", color: "var(--teal)", fontSize: 17, padding: 0 }}>
                  {ROAD_STATUSES.map(r => <option key={r} value={r}>{roadLabel[r]}</option>)}
                </select>
              </Field>
              <div className="row"><Zap size={18} /> Utility lines involved <Toggle on={wires} onChange={setWires} label="Utility lines involved" /></div>
              <Field label="Description">
                <textarea value={details} onChange={e => setDetails(e.target.value)} rows={4}
                          style={{ width: "100%", border: 0, borderRadius: 10, padding: 10, background: "#f2f2f7", resize: "none", fontSize: 15 }} />
              </Field>
              <div className="tiny muted">⌖ {town} · {store.location.latitude.toFixed(4)}, {store.location.longitude.toFixed(4)}</div>
            </div>

            <button className="btn primary" disabled={!details.trim() || posting} onClick={post}><Send size={18} /> {posting ? "Posting…" : "Post report"}</button>
            <p className="caption" style={{ textAlign: "center" }}>
              {guest ? "Guest demo: this report stays in this browser." : "The photo is sent to OpenAI for analysis and is never published. Only the fields above go on the map."}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><div className="small muted" style={{ fontWeight: 600, marginBottom: 5 }}>{label}</div>{children}</div>;
}

function Ring({ value, color }: { value: number; color: string }) {
  const r = 25, c = 2 * Math.PI * r;
  return (
    <svg width={58} height={58} viewBox="0 0 58 58">
      <circle cx={29} cy={29} r={r} fill="none" stroke={color} strokeOpacity={0.18} strokeWidth={7} />
      <circle cx={29} cy={29} r={r} fill="none" stroke={color} strokeWidth={7} strokeLinecap="round"
              strokeDasharray={`${c * Math.max(0.02, value)} ${c}`} transform="rotate(-90 29 29)" />
      <text x={29} y={33} textAnchor="middle" fontSize={16} fontWeight={700}>{Math.round(value * 100)}</text>
    </svg>
  );
}

