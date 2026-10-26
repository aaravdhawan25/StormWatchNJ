import { CircleCheck, Smartphone, TriangleAlert } from "lucide-react";
import { AppLogo, StormBackdrop } from "../components/ui";

const onApple = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

// where the confirmation email's link lands
export function EmailLinkScreen({ ok, message, signedIn, onDone }:
  { ok: boolean; message?: string; signedIn: boolean; onDone: () => void }) {
  const expired = !ok && /expired|invalid/i.test(message ?? "expired");
  return (
    <div className="screen" style={{ color: "#fff" }}>
      <StormBackdrop waterLevel={0.18} animated={false} />
      <div className="stack" style={{ position: "relative", flex: 1, justifyContent: "center", alignItems: "center", padding: "60px 28px", gap: 14, textAlign: "center" }}>
        <AppLogo size={76} />
        {ok ? <CircleCheck size={40} color="#4ade80" /> : <TriangleAlert size={40} color="var(--amber)" />}
        <div className="rounded" style={{ fontSize: 28, fontWeight: 800 }}>{ok ? "Email confirmed" : expired ? "This link has expired" : "That didn't work"}</div>
        <div style={{ fontSize: 14, opacity: 0.82, lineHeight: 1.45, maxWidth: 320 }}>
          {ok ? (onApple
                  ? "Signed up in the StormWatch NJ app? Open it — it signs you in by itself. Or keep going here on the web."
                  : "Your account is ready." + (signedIn ? " You're signed in." : " Sign in to continue."))
              : expired ? "Links work once and expire after a while. Sign in with your email and password — if your address still needs confirming, a new link is sent."
              : message}
        </div>
        <div className="stack" style={{ width: "100%", maxWidth: 320, gap: 11, marginTop: 10 }}>
          {ok && onApple && (
            <a href="stormwatchnj://auth-callback" className="row rounded"
               style={{ justifyContent: "center", padding: 15, borderRadius: 99, background: "#fff", color: "var(--navy)", fontWeight: 700, fontSize: 16, textDecoration: "none" }}>
              <Smartphone size={18} /> Open the StormWatch NJ app</a>
          )}
          <button className="rounded" onClick={onDone}
                  style={{ padding: 15, borderRadius: 99, fontWeight: 700, fontSize: 16,
                           ...(ok && onApple ? { background: "rgba(10,26,51,.55)", border: "1px solid rgba(255,255,255,.55)", color: "#fff" }
                                             : { background: "#fff", color: "var(--navy)" }) }}>
            {ok ? (onApple ? "Continue on the web" : "Continue") : "Back to sign in"}
          </button>
        </div>
      </div>
    </div>
  );
}
