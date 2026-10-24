import { useEffect, useState } from "react";
import { ChevronDown, ChevronLeft, ChevronUp, Hash, Landmark, Lock, Mail } from "lucide-react";
import { AppLogo, StormBackdrop } from "../components/ui";
import { GoogleButton } from "../components/GoogleButton";
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
      const { data, error } = await supabase.auth.signUp({ email: address, password,
        options: { data: { account_type: kind }, emailRedirectTo: window.location.origin } });
      if (error) throw error;
      if (!data.session) setPending(address);
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email: address, password });
      if (error?.code === "email_not_confirmed") {
        setPending(address);
        await supabase.auth.resend({ type: "signup", email: address, options: { emailRedirectTo: window.location.origin } });
        return;
      }
      if (error) throw error;
      if (kind === "township") await supabase.auth.updateUser({ data: { account_type: "township" } });
    }
  });

  // Same rules as the iPhone app: a township sign-in needs a Google account on a
  // listed municipal domain. If it isn't one, the new session is signed out again.
  const signInWithGoogle = async (token: string, nonce: string) => {
    const { data, error } = await supabase.auth.signInWithIdToken({ provider: "google", token, nonce });
    if (error) throw error;
    if (kind !== "township") return;
    try { await requireTownship(data.user?.email ?? ""); }
    catch (e) { await supabase.auth.signOut(); throw e; }
    if (data.user?.user_metadata?.account_type !== "township") await supabase.auth.updateUser({ data: { account_type: "township" } });
  };

  // After the person taps the link (often in another tab or on their phone),
  // their password signs them in. Checked by the button and whenever they
  // come back to this tab.
  const checkConfirmed = async (quiet: boolean) => {
    if (!pending || !password) return;
    const { error } = await supabase.auth.signInWithPassword({ email: pending, password });
    if (!error) {
      if (kind === "township") await supabase.auth.updateUser({ data: { account_type: "township" } });
      return;
    }
    if (!quiet) throw error.code === "email_not_confirmed"
      ? new Error("Not confirmed yet. Tap the link in the email from Supabase, then try again.") : error;
  };
  useEffect(() => {
    if (!pending) return;
    const onBack = () => { if (document.visibilityState === "visible") checkConfirmed(true).catch(() => {}); };
    document.addEventListener("visibilitychange", onBack);
    return () => document.removeEventListener("visibilitychange", onBack);
  }, [pending, password]); // eslint-disable-line react-hooks/exhaustive-deps
  const [showCode, setShowCode] = useState(false);

  const verify = () => run(async () => {
    const { error } = await supabase.auth.verifyOtp({ type: "signup", email: pending!, token: code.trim() });
    if (error) throw error;
  });

  const heading = pending ? "Check your email" : kind === "township" ? (creating ? "Township account" : "Township sign-in") : creating ? "Create your account" : "Welcome back";
  const sub = pending ? `We sent an email to ${pending}. Tap the link in it — you'll be signed in.`
    : kind === "township" ? "For municipal staff. Use your official township email — you'll confirm it from an email sent there, so only someone who receives mail at that address can sign in."
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
            {primary("I've confirmed my email", !!password, () => run(() => checkConfirmed(false)))}
            {showCode ? <>
              {field(<Hash size={16} />, <input style={{ ...inputStyle, fontSize: 20, fontWeight: 600 }} placeholder="Code from the email" inputMode="numeric"
                                               autoComplete="one-time-code" value={code} onChange={e => setCode(e.target.value)} autoFocus />)}
              {primary("Verify code", code.length >= 6, verify)}
            </> : <button style={{ fontSize: 13, fontWeight: 600, opacity: 0.85 }} onClick={() => setShowCode(true)}>My email has a code instead</button>}
            <div className="row" style={{ fontSize: 13, fontWeight: 600, opacity: 0.85 }}>
              <button onClick={() => run(async () => { await supabase.auth.resend({ type: "signup", email: pending, options: { emailRedirectTo: window.location.origin } }); setMessage("A new email is on its way. You can ask once a minute."); })}>Send a new email</button>
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
            {GOOGLE_ENABLED && <>
              <div className="row" style={{ fontSize: 12, opacity: 0.6, gap: 10 }}>
                <span style={{ flex: 1, height: 1, background: "rgba(255,255,255,.3)" }} />or<span style={{ flex: 1, height: 1, background: "rgba(255,255,255,.3)" }} />
              </div>
              <GoogleButton key={kind} disabled={busy} onError={m => setMessage(m)} onToken={(token, nonce) => run(() => signInWithGoogle(token, nonce))} />
            </>}
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
  if (/email rate limit/i.test(message)) return "Too many emails have been sent in the last hour, so a new one can't go out yet. Try again later, or use the link in an email you already have.";
  if (/rate limit|too many/i.test(message)) return "Too many attempts. Wait a minute and try again.";
  if (/recognised township/i.test(message)) return message;
  if (/database error saving new user/i.test(message)) return "That email is not on a recognised township domain.";
  if (/nonce|audience|unacceptable audience|id token/i.test(message)) return "Google sign-in isn't set up for this website yet. Use email for now.";
  return message;
}
