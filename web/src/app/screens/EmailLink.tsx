import { useState } from "react";
import { CircleCheck, KeyRound, Lock, Smartphone, TriangleAlert } from "lucide-react";
import { supabase } from "../lib/config";
import { AppLogo, StormBackdrop } from "../components/ui";

const onApple = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

// where the confirmation email's link lands
export function EmailLinkScreen({ ok, message, signedIn, onDone, recovery }:
  { ok: boolean; message?: string; signedIn: boolean; onDone: () => void; recovery?: boolean }) {
  if (ok && recovery) return <NewPasswordScreen onDone={onDone} />;
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

// the forgot-password link lands here to choose a new password
function NewPasswordScreen({ onDone }: { onDone: () => void }) {
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const save = async () => {
    setBusy(true); setError(null);
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);
    if (error) setError(/same/i.test(error.message) ? "Choose a password you haven't used before." : error.message);
    else setSaved(true);
  };
  return (
    <div className="screen" style={{ color: "#fff" }}>
      <StormBackdrop waterLevel={0.18} animated={false} />
      <div className="stack" style={{ position: "relative", flex: 1, justifyContent: "center", alignItems: "center", padding: "60px 28px", gap: 14, textAlign: "center" }}>
        <AppLogo size={76} />
        {saved ? <CircleCheck size={40} color="#4ade80" /> : <KeyRound size={40} color="var(--bright)" />}
        <div className="rounded" style={{ fontSize: 28, fontWeight: 800 }}>{saved ? "Password saved" : "Set a new password"}</div>
        <div style={{ fontSize: 14, opacity: 0.82, lineHeight: 1.45, maxWidth: 320 }}>
          {saved ? "You can now sign in with your email and this password, here and in the iPhone app." : "Choose a password with at least 8 characters."}
        </div>
        {!saved && (
          <div className="row" style={{ width: "100%", maxWidth: 320, padding: "14px 16px", borderRadius: 14, background: "rgba(255,255,255,.1)", border: "1px solid rgba(255,255,255,.16)" }}>
            <Lock size={16} color="var(--bright)" />
            <input type="password" autoComplete="new-password" placeholder="New password" value={password} autoFocus
                   onChange={e => setPassword(e.target.value)} onKeyDown={e => e.key === "Enter" && password.length >= 8 && save()}
                   style={{ flex: 1, minWidth: 0, background: "none", border: 0, outline: "none", color: "#fff", fontSize: 16 }} />
          </div>
        )}
        {error && <div style={{ color: "var(--amber)", fontSize: 13, maxWidth: 320 }}>⚠︎ {error}</div>}
        <button className="rounded" disabled={!saved && (password.length < 8 || busy)} onClick={saved ? onDone : save}
                style={{ width: "100%", maxWidth: 320, padding: 15, borderRadius: 99, background: "#fff", color: "var(--navy)", fontWeight: 700, fontSize: 16,
                         opacity: !saved && (password.length < 8 || busy) ? 0.5 : 1 }}>
          {saved ? "Continue" : busy ? "…" : "Save password"}
        </button>
      </div>
    </div>
  );
}
