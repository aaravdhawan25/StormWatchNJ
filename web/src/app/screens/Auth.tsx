import { useEffect, useState } from "react";
import { ChevronDown, ChevronLeft, ChevronUp, Hash, Landmark, Lock, Mail } from "lucide-react";
import { AppLogo, StormBackdrop } from "../components/ui";
import { GOOGLE_ENABLED, supabase } from "../lib/config";

interface Town { domain: string; name: string; county: string }

/** Sign in, create an account, and confirm the emailed code — same rules as the iPhone app. */
export function AuthScreen({ kind: initialKind, creating: initialCreating, onBack }:
  { kind: "resident" | "township"; creating: boolean; onBack: () => void }) {
  const [kind, setKind] = useState(initialKind);
  const [creating, setCreating] = useState(initialCreating);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [pending, setPending] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [towns, setTowns] = useState<Town[]>([]);
  const [showTowns, setShowTowns] = useState(false);

  useEffect(() => {
    supabase.from("township_domains").select("domain,name,county").order("name").then(({ data }) => setTowns(data ?? []));
  }, []);

  const run = async (action: () => Promise<void>) => {
    setMessage(null); setBusy(true);
    try { await action(); } catch (e) { setMessage(friendly((e as Error).message)); }
    setBusy(false);
  };

  const requireTownship = async (address: string) => {
    const { data } = await supabase.rpc("township_for_email", { p_email: address });
    if (!data) throw new Error("That email is not on a recognised township domain. Use your official municipal address, or sign in as a resident instead.");
  };

  const submit = () => run(async () => {
    const address = email.trim().toLowerCase();
    if (kind === "township") await requireTownship(address);
    if (creating) {
      const { data, error } = await supabase.auth.signUp({ email: address, password, options: { data: { account_type: kind } } });
      if (error) throw error;
      if (!data.session) setPending(address);
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email: address, password });
      if (error?.code === "email_not_confirmed") {
        setPending(address);
        await supabase.auth.resend({ type: "signup", email: address });
        return;
      }
      if (error) throw error;
      if (kind === "township") await supabase.auth.updateUser({ data: { account_type: "township" } });
    }
  });

  const verify = () => run(async () => {
    const { error } = await supabase.auth.verifyOtp({ type: "signup", email: pending!, token: code.trim() });
    if (error) throw error;
  });

  const heading = pending ? "Check your email" : kind === "township" ? (creating ? "Township account" : "Township sign-in") : creating ? "Create your account" : "Welcome back";
  const sub = pending ? `We sent an email to ${pending}. Enter the code from it, or tap the link in it and come back.`
    : kind === "township" ? "For municipal staff. Use your official township email — you'll confirm it with a code sent there, so only someone who receives mail at that address can sign in."
    : creating ? "One account lets you report hazards, remove your own, and vote when one is gone." : "Sign in to see what's happening on your streets.";

  const field = (icon: React.ReactNode, input: React.ReactNode) => (
    <div className="row" style={{ padding: "14px 16px", borderRadius: 14, background: "rgba(255,255,255,.1)", border: "1px solid rgba(255,255,255,.16)" }}>
      <span style={{ color: "var(--bright)", display: "flex" }}>{icon}</span>{input}
    </div>
  );
  const inputStyle: React.CSSProperties = { flex: 1, minWidth: 0, background: "none", border: 0, outline: "none", color: "#fff", fontSize: 16 };
  const primary = (label: string, enabled: boolean, onClick: () => void) => (
    <button className="rounded" disabled={!enabled || busy} onClick={onClick}
            style={{ padding: 15, borderRadius: 99, background: `rgba(255,255,255,${enabled ? 1 : 0.45})`, color: "var(--navy)", fontWeight: 700, fontSize: 16 }}>
      {busy ? "…" : label}
    </button>
  );

  return (
    <div className="screen" style={{ color: "#fff" }}>
      <StormBackdrop waterLevel={0.14} animated={false} />
      <div className="scroll" style={{ position: "relative", padding: "56px 22px 40px" }}>
        <button onClick={onBack} aria-label="Back" style={{ width: 40, height: 40, borderRadius: 20, background: "rgba(10,26,51,.6)", border: "1px solid rgba(255,255,255,.2)", display: "grid", placeItems: "center" }}>
          <ChevronLeft size={22} />
        </button>
        <div style={{ textAlign: "center", marginTop: 8 }}>
          <AppLogo size={64} />
          <div className="rounded" style={{ fontSize: 28, fontWeight: 800, marginTop: 14 }}>{heading}</div>
          <div style={{ fontSize: 13, opacity: 0.78, margin: "8px 6px 18px", lineHeight: 1.4 }}>{sub}</div>
        </div>

        <div className="stack" style={{ gap: 14, padding: 18, borderRadius: 24, background: "rgba(30,40,60,.55)", border: "1px solid rgba(255,255,255,.18)", backdropFilter: "blur(20px)" }}>
          {pending ? <>
            {field(<Hash size={16} />, <input style={{ ...inputStyle, fontSize: 20, fontWeight: 600 }} placeholder="Code from the email" inputMode="numeric"
                                             autoComplete="one-time-code" value={code} onChange={e => setCode(e.target.value)} autoFocus />)}
            {primary("Verify", code.length >= 6, verify)}
            <button style={{ fontSize: 13, fontWeight: 600, opacity: 0.85 }} disabled={busy || !password}
                    onClick={() => { setCreating(false); setPending(null); submit(); }}>I tapped the link in the email</button>
            <div className="row" style={{ fontSize: 13, fontWeight: 600, opacity: 0.85 }}>
              <button onClick={() => run(async () => { await supabase.auth.resend({ type: "signup", email: pending }); setMessage("A new email is on its way. You can ask once a minute."); })}>Send a new email</button>
              <span className="spacer" />
              <button onClick={() => { setPending(null); setCode(""); setMessage(null); }}>Use a different email</button>
            </div>
          </> : <>
            <div className="row" style={{ background: "rgba(255,255,255,.08)", borderRadius: 10, padding: 2, gap: 2 }}>
              {(["resident", "township"] as const).map(k => (
                <button key={k} onClick={() => { setKind(k); setMessage(null); }}
                        style={{ flex: 1, padding: "7px 0", borderRadius: 8, fontSize: 13, fontWeight: 600, background: kind === k ? "rgba(255,255,255,.22)" : "none" }}>
                  {k === "resident" ? "Resident" : "Township"}
                </button>
              ))}
            </div>
            {field(<Mail size={16} />, <input style={inputStyle} placeholder={kind === "township" ? "you@yourtownship.gov" : "Email"} type="email"
                                            autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} />)}
            {field(<Lock size={16} />, <input style={inputStyle} placeholder={creating ? "Password (8+ characters)" : "Password"} type="password"
                                            autoComplete={creating ? "new-password" : "current-password"} value={password}
                                            onChange={e => setPassword(e.target.value)} onKeyDown={e => e.key === "Enter" && submit()} />)}
            {primary(creating ? "Create account" : "Sign in", !!email && password.length >= (creating ? 8 : 1), submit)}
            {GOOGLE_ENABLED && (
              <button className="row rounded" onClick={() => run(async () => {
                        const { error } = await supabase.auth.signInWithOAuth({ provider: "google", options: { redirectTo: window.location.origin } });
                        if (error) throw error; })}
                      style={{ justifyContent: "center", padding: 14, borderRadius: 99, background: "#131314", border: "1px solid #8e918f", color: "#e3e3e3", fontWeight: 600 }}>
                <img src="/google-g.svg" width={18} height={18} alt="" /> Continue with Google
              </button>
            )}
            <button style={{ fontSize: 13, fontWeight: 600, opacity: 0.85 }} onClick={() => { setCreating(!creating); setMessage(null); }}>
              {creating ? "I already have an account" : "New here? Create an account"}
            </button>
          </>}
          {message && <div style={{ color: "var(--amber)", fontSize: 13, fontWeight: 500, lineHeight: 1.35 }}>⚠︎ {message}</div>}
        </div>

        {!pending && kind === "township" && towns.length > 0 && (
          <div style={{ marginTop: 18, borderRadius: 18, background: "rgba(255,255,255,.1)" }}>
            <button className="row" style={{ width: "100%", padding: 14, fontSize: 13, fontWeight: 600 }} onClick={() => setShowTowns(!showTowns)}>
              <Landmark size={15} /> {towns.length} recognised townships <span className="spacer" /> {showTowns ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
            </button>
            {showTowns && towns.map(t => (
              <div key={t.domain} className="row" style={{ padding: "6px 14px", fontSize: 12 }}>
                <span>{t.name}</span><span className="spacer" /><span style={{ opacity: 0.65 }}>@{t.domain}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function friendly(message: string): string {
  if (/invalid login credentials/i.test(message)) return "Incorrect email or password.";
  if (/already registered|already exists/i.test(message)) return "An account with that email already exists. Sign in instead.";
  if (/expired|invalid.*otp|token has expired/i.test(message)) return "That code is wrong or has expired. Request a new one.";
  if (/rate limit|too many/i.test(message)) return "Too many attempts. Wait a minute and try again.";
  if (/recognised township/i.test(message)) return message;
  if (/database error saving new user/i.test(message)) return "That email is not on a recognised township domain.";
  return message;
}
