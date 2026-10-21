import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { ChevronLeft, CloudRain, Droplet, Leaf, TriangleAlert, Waves, Zap } from "lucide-react";
import type { Hazard, HazardType, Severity } from "../lib/models";
import { hazardGradient, hazardLabel, relativeTime, severityColor, severityLabel } from "../lib/models";

// ---------------- navigation: push, sheet, dialog ----------------

interface DialogSpec { title: string; message?: string; actions: { label: string; strong?: boolean; danger?: boolean; run?: () => void }[] }
interface Nav {
  push: (node: ReactNode) => void; pop: () => void;
  present: (node: ReactNode) => void; dismiss: () => void;
  dialog: (d: DialogSpec) => void;
  depth: number;
}
const NavCtx = createContext<Nav | null>(null);
export const useNav = () => useContext(NavCtx)!;

export function NavHost({ children, resetKey }: { children: ReactNode; resetKey: unknown }) {
  const [stack, setStack] = useState<ReactNode[]>([]);
  const [sheet, setSheet] = useState<ReactNode | null>(null);
  const [dialog, setDialog] = useState<DialogSpec | null>(null);
  useEffect(() => { setStack([]); }, [resetKey]);
  const nav: Nav = {
    push: n => setStack(s => [...s, n]), pop: () => setStack(s => s.slice(0, -1)),
    present: n => setSheet(n), dismiss: () => setSheet(null), dialog: setDialog, depth: stack.length,
  };
  return (
    <NavCtx.Provider value={nav}>
      {children}
      {stack.map((node, i) => <div key={i} className="screen" style={{ zIndex: 20 + i }}>{node}</div>)}
      {sheet && <>
        <div className="sheet-backdrop" onClick={() => setSheet(null)} />
        <div className="sheet"><div className="grabber" />{sheet}</div>
      </>}
      {dialog && (
        <div className="dialog-wrap">
          <div className="dialog">
            <h3>{dialog.title}</h3>
            {dialog.message && <p>{dialog.message}</p>}
            <div className="actions">
              {dialog.actions.map(a => (
                <button key={a.label} className={a.strong ? "strong" : ""} style={a.danger ? { color: "var(--red)" } : undefined}
                        onClick={() => { setDialog(null); a.run?.(); }}>{a.label}</button>
              ))}
            </div>
          </div>
        </div>
      )}
    </NavCtx.Provider>
  );
}

export function NavBar({ title, trailing }: { title: string; trailing?: ReactNode }) {
  const nav = useNav();
  return (
    <div className="navbar">
      <button className="back" onClick={nav.pop} aria-label="Back"><ChevronLeft size={22} /></button>
      {title}
      {trailing && <div style={{ position: "absolute", right: 16, bottom: 10 }}>{trailing}</div>}
    </div>
  );
}

// ---------------- visual pieces ----------------

export function WaveEdge({ fill = "var(--bg)" }: { fill?: string }) {
  const path = (amp: number, phase: number, cycles: number, top: number) => {
    let d = `M0 30 L0 ${top}`;
    for (let x = 0; x <= 400; x += 8) d += ` L${x} ${top + Math.sin((x / 400) * Math.PI * 2 * cycles + phase) * amp}`;
    return d + " L400 30 Z";
  };
  return (
    <svg className="wave" viewBox="0 0 400 30" preserveAspectRatio="none" aria-hidden>
      <path d={path(5, 0.6, 1.2, 8)} fill="rgba(255,255,255,.08)" />
      <path d={path(4, 2.6, 1.6, 14)} fill="rgba(46,199,209,.3)" />
      <path d={path(3.5, 4.3, 1.3, 20)} fill={fill} />
    </svg>
  );
}

export function Header({ title, subtitle, trailing }: { title: string; subtitle?: string; trailing?: ReactNode }) {
  return (
    <div className="header">
      <h1>{title}</h1>
      {subtitle && <p>{subtitle}</p>}
      {trailing && <div className="trail">{trailing}</div>}
      <WaveEdge />
    </div>
  );
}

export const hazardIcon = (t: HazardType, size: number) => {
  switch (t) {
    case "STREET_FLOODING": return <Waves size={size} strokeWidth={2.4} />;
    case "CLOGGED_DRAIN": return <Droplet size={size} strokeWidth={2.4} fill="currentColor" />;
    case "DOWNED_TREE": return <Leaf size={size} strokeWidth={2.4} fill="currentColor" />;
    case "DOWNED_WIRE": return <Zap size={size} strokeWidth={2.4} fill="currentColor" />;
    default: return <TriangleAlert size={size} strokeWidth={2.4} />;
  }
};

export function HazardGlyph({ type, size = 52 }: { type: HazardType; size?: number }) {
  const [a, b] = hazardGradient[type];
  return (
    <div className="glyph" style={{ width: size, height: size, borderRadius: size * 0.28,
      background: `linear-gradient(135deg, ${a}, ${b})`, boxShadow: `0 ${size * 0.06}px ${size * 0.2}px ${a}59` }}>
      {hazardIcon(type, size * 0.44)}
    </div>
  );
}

export function SeverityBadge({ severity }: { severity: Severity }) {
  const c = severityColor[severity];
  return <span className="badge" style={{ background: c + "2e", color: c }}>{severityLabel[severity].toUpperCase()}</span>;
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label?: string }) {
  return <button role="switch" aria-checked={on} aria-label={label} className={`toggle ${on ? "on" : ""}`} onClick={() => onChange(!on)} />;
}

export function HazardCard({ hazard, miles, onClick }: { hazard: Hazard; miles?: number; onClick: () => void }) {
  return (
    <button className="hcard" onClick={onClick}>
      <div className="stripe" style={{ background: severityColor[hazard.severity] }} />
      <div className="body">
        {hazard.photoURL
          ? <img src={hazard.photoURL} alt="" style={{ width: 52, height: 52, borderRadius: 14, objectFit: "cover", flexShrink: 0 }} />
          : <HazardGlyph type={hazard.reportType} />}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="row" style={{ gap: 6 }}>
            <b className="rounded" style={{ fontSize: 15, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{hazardLabel[hazard.reportType]}</b>
            <span className="spacer" />
            <SeverityBadge severity={hazard.severity} />
          </div>
          <div className="small muted clamp2" style={{ margin: "4px 0 5px" }}>{hazard.details}</div>
          <div className="row tiny muted" style={{ gap: 10 }}>
            {miles != null && <span>➤ {miles.toFixed(1)} mi</span>}
            <span>◷ {relativeTime(hazard.createdAt)}</span>
            {hazard.utilityLinesInvolved && <span style={{ color: "var(--red)" }}>⚡ Wires</span>}
            {hazard.status === "IN_PROGRESS" && <span style={{ color: "var(--teal)" }}>Crew</span>}
          </div>
        </div>
      </div>
    </button>
  );
}

/** Rain over rising water — the same scene as the app icon. Stops under reduced motion. */
export function StormBackdrop({ waterLevel = 0.24, animated = true }: { waterLevel?: number; animated?: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current!;
    const ctx = canvas.getContext("2d")!;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let frame = 0;
    const draw = (t: number) => {
      const w = canvas.clientWidth, h = canvas.clientHeight, dpr = window.devicePixelRatio || 1;
      if (canvas.width !== w * dpr) { canvas.width = w * dpr; canvas.height = h * dpr; }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      const time = t / 1000;
      ctx.strokeStyle = "rgba(158,209,230,.28)"; ctx.lineWidth = 1.4; ctx.beginPath();
      for (let i = 0; i < 90; i++) {
        const col = Math.abs((Math.sin(i * 12.9898) * 43758.5453) % 1), off = Math.abs((Math.sin(i * 78.233) * 12345.678) % 1);
        const speed = 380 + col * 260, len = 14 + off * 22, travel = h + 80;
        const y = ((time * speed + off * travel) % travel) - 40, x = col * (w + 120) - 60 + y * 0.22;
        ctx.moveTo(x, y); ctx.lineTo(x + len * 0.22, y + len);
      }
      ctx.stroke();
      const top = h * (1 - waterLevel);
      ([[0, 12, 0.7, "rgba(15,117,138,.92)"], [34, 10, -1, "rgba(23,158,176,.92)"], [70, 8, 1.3, "rgba(46,199,209,.92)"]] as const)
        .forEach(([offset, amp, speed, color]) => {
          ctx.fillStyle = color; ctx.beginPath(); ctx.moveTo(0, h);
          for (let x = 0; x <= w; x += 4) ctx.lineTo(x, top + offset + amp + Math.sin((x / w) * Math.PI * 2 * 1.4 + time * speed) * amp);
          ctx.lineTo(w, h); ctx.closePath(); ctx.fill();
        });
      if (animated && !reduce) frame = requestAnimationFrame(draw);
    };
    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [waterLevel, animated]);
  return (
    <div style={{ position: "absolute", inset: 0, background: "radial-gradient(circle at 50% 28%, rgba(46,199,209,.22), transparent 55%), linear-gradient(#050f24, #0a1a33 35%, #0d2e4f 70%, #0d5266)" }}>
      <canvas ref={ref} style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} />
    </div>
  );
}

export function AppLogo({ size = 96 }: { size?: number }) {
  return <img src="/app-icon.png" alt="" width={size} height={size}
              style={{ borderRadius: size * 0.225, boxShadow: `0 ${size * 0.07}px ${size * 0.16}px rgba(0,0,0,.35)`, border: "1px solid rgba(255,255,255,.18)" }} />;
}

export const RainIcon = CloudRain;
