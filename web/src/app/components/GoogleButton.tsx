import { useEffect, useRef, useState } from "react";
import { GOOGLE_CLIENT_ID } from "../lib/config";

// Google's own sign-in button

declare global {
  interface Window {
    google?: { accounts: { id: {
      initialize: (o: Record<string, unknown>) => void;
      renderButton: (el: HTMLElement, o: Record<string, unknown>) => void;
      cancel: () => void;
    } } };
  }
}

let loader: Promise<void> | null = null;
function loadGoogle() {
  loader ??= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://accounts.google.com/gsi/client";
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => { loader = null; reject(new Error("Couldn't reach Google. Check your connection.")); };
    document.head.appendChild(s);
  });
  return loader;
}

async function sha256(text: string) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
}

// calls `onToken(idToken, nonce)` after the person picks a Google account
export function GoogleButton({ onToken, onError, disabled }:
  { onToken: (idToken: string, nonce: string) => void; onError: (message: string) => void; disabled?: boolean }) {
  const box = useRef<HTMLDivElement>(null);
  // Google only shows its button if this site is allowed
  const [state, setState] = useState<"loading" | "ready" | "failed">("loading");
  const latest = useRef(onToken);
  latest.current = onToken;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        await loadGoogle();
        if (cancelled || !box.current || !window.google) return;
        // a fresh nonce per button
        const nonce = crypto.randomUUID();
        window.google.accounts.id.initialize({
          client_id: GOOGLE_CLIENT_ID,
          nonce: await sha256(nonce),
          callback: (r: { credential?: string }) => r.credential ? latest.current(r.credential, nonce) : onError("Google didn't return an account."),
          ux_mode: "popup",
          use_fedcm_for_button: true,
        });
        const width = Math.min(400, Math.max(200, Math.round(box.current.getBoundingClientRect().width / scale(box.current))));
        window.google.accounts.id.renderButton(box.current, {
          type: "standard", theme: "filled_black", size: "large", shape: "pill",
          text: "continue_with", logo_alignment: "center", width,
        });
        for (let i = 0; i < 32 && !cancelled; i++) {
          const frame = box.current?.querySelector("iframe");
          if (frame && frame.offsetWidth > 0) { setState("ready"); return; }
          await new Promise(r => setTimeout(r, 250));
        }
        if (!cancelled) setState("failed");
      } catch { if (!cancelled) setState("failed"); }
    })();
    return () => { cancelled = true; window.google?.accounts.id.cancel(); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div style={{ position: "relative", minHeight: 44, opacity: disabled ? 0.5 : 1, pointerEvents: disabled ? "none" : "auto" }}>
      {state !== "ready" && (
        <button type="button" className="row rounded" style={{ justifyContent: "center", padding: 12, borderRadius: 99, background: "#131314",
                                              border: "1px solid #8e918f", color: "#e3e3e3", fontWeight: 600, width: "100%" }}
                onClick={() => state === "failed" && onError(window.google
                  ? `Google sign-in isn't switched on for ${window.location.host} yet. Use email for now.`
                  : "Couldn't reach Google. Check your connection and try again.")}>
          <img src="/google-g.svg" width={18} height={18} alt="" /> Continue with Google
        </button>
      )}
      <div ref={box} style={{ display: "flex", justifyContent: "center", colorScheme: "light",
                              ...(state === "ready" ? {} : { position: "absolute", inset: 0, opacity: 0, pointerEvents: "none" }) }} />
    </div>
  );
}

// the desktop page shrinks the phone with a CSS transform
function scale(el: HTMLElement) {
  const r = el.getBoundingClientRect();
  return el.offsetWidth ? r.width / el.offsetWidth : 1;
}
