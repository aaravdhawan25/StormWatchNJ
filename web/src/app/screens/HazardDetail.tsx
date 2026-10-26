import { useState } from "react";
import { MapContainer, Marker, TileLayer } from "react-leaflet";
import L from "leaflet";
import { BadgeCheck, Building2, CircleCheck, EyeOff, MessageSquare, Globe, ThumbsUp, Trash2, Users } from "lucide-react";
import { HazardGlyph, NavBar, SeverityBadge, hazardIcon, useNav } from "../components/ui";
import { LifeSafetyBanner } from "../components/LifeSafety";
import type { Hazard, ReportStatus } from "../lib/models";
import { REPORT_STATUSES, hazardGradient, hazardLabel, isLifeSafetyRisk, milesBetween, relativeTime, roadLabel, severityColor, statusLabel } from "../lib/models";
import { useStore } from "../lib/store";

const EXPIRY_NOTE = "Hazards also come off the map on their own 3 days after their last update.";

export function nextdoorURL(h: Hazard) {
  const lines = [`⚠️ ${hazardLabel[h.reportType]} — ${h.severity}`, "", h.details, "", `Road status: ${roadLabel[h.roadStatus]}`, `Area: ${h.municipality}, NJ`];
  if (h.utilityLinesInvolved) lines.push("", "⚡️ Utility lines are involved. Treat any downed wire as energized — stay well back and call 911 and your utility.");
  lines.push("", "Reported via StormWatch NJ, a neighbor-powered storm hazard map.");
  return `https://nextdoor.com/sharekit/?${new URLSearchParams({ source: "stormwatchnj", body: lines.join("\n").slice(0, 3500) })}`;
}

export function HazardDetail({ hazardId, pushed = false }: { hazardId: string; pushed?: boolean }) {
  const store = useStore();
  const nav = useNav();
  const [busy, setBusy] = useState(false);
  const [forwarding, setForwarding] = useState(false);
  const h = store.hazards.find(x => x.id === hazardId);
  const close = () => (pushed ? nav.pop() : nav.dismiss());
  if (!h) return <div className="scroll"><p className="muted" style={{ textAlign: "center", marginTop: 60 }}>This hazard is no longer on the map.</p></div>;

  const township = store.account?.role === "township";
  const guest = store.account?.guest;
  const canRemoveShared = h.isMine || township;
  // Mirrors the server's 1-mile voting rule; the server makes the real decision.
  const voteMiles = store.realLocation ? milesBetween(store.realLocation, h) : null;
  const tooFar = voteMiles != null && voteMiles > 1;
  const act = (fn: () => Promise<unknown>, after?: () => void) => {
    setBusy(true);
    fn().then(() => after?.()).catch(e => nav.dialog({ title: "That didn't work", message: (e as Error).message, actions: [{ label: "OK" }] }))
      .finally(() => setBusy(false));
  };
  const pinIcon = L.divIcon({ className: "", iconSize: [30, 30], iconAnchor: [15, 15],
    html: `<div class="pin" style="width:30px;height:30px;background:${severityColor[h.severity]}"></div>` });

  return (
    <>
      {pushed ? <NavBar title="Hazard" /> : <div style={{ textAlign: "center", fontWeight: 600, padding: "10px 0 6px" }}>Hazard</div>}
      <div className="scroll" style={{ paddingTop: 6 }}>
        <div className="stack">
          {isLifeSafetyRisk(h.reportType, h.utilityLinesInvolved) && h.status !== "RESOLVED" && (
            <div style={{ borderRadius: 14, overflow: "hidden" }}><LifeSafetyBanner location={h.address ?? `${h.municipality}, NJ`} /></div>
          )}
          {h.photoURL
            ? <img src={h.photoURL} alt="" style={{ width: "100%", height: 200, objectFit: "cover", borderRadius: 14 }} />
            : <div style={{ height: 130, borderRadius: 14, display: "grid", placeItems: "center", color: "#fff",
                            background: `linear-gradient(135deg, ${hazardGradient[h.reportType][0]}, ${hazardGradient[h.reportType][1]})` }}>
                {hazardIcon(h.reportType, 54)}</div>}

          <div className="card">
            <div className="row">
              <HazardGlyph type={h.reportType} size={46} />
              <div style={{ flex: 1 }}><b>{hazardLabel[h.reportType]}</b><div className="small muted">{h.municipality}</div></div>
              <SeverityBadge severity={h.severity} />
            </div>
            <p style={{ margin: "12px 0 0", fontSize: 14, lineHeight: 1.4, userSelect: "text" }}>{h.details}</p>
          </div>

          <div className="group-head" style={{ margin: "6px 16px 0" }}>Details</div>
          <div className="group">
            {[["Road", roadLabel[h.roadStatus]], ["Status", statusLabel[h.status]], ["Municipality", h.municipality],
              ...(h.address ? [["Address", h.address]] : []),
              ["Distance", `${milesBetween(store.location, h).toFixed(1)} mi away`], ["Reported", relativeTime(h.createdAt)],
              ["Confirmations", String(h.upvotes)]].map(([k, v]) => (
              <div key={k} className="cell"><span>{k}</span><span className="val">{v}</span></div>
            ))}
          </div>

          <div style={{ height: 170, borderRadius: 14, overflow: "hidden", pointerEvents: "none" }}>
            <MapContainer center={[h.latitude, h.longitude]} zoom={15} zoomControl={false} style={{ height: "100%" }}>
              <TileLayer url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" attribution="&copy; OpenStreetMap" />
              <Marker position={[h.latitude, h.longitude]} icon={pinIcon} />
            </MapContainer>
          </div>

          <div className="group">
            <a className="cell link" href={nextdoorURL(h)} target="_blank" rel="noreferrer"><Users size={18} /> Share to Nextdoor</a>
          </div>
          <div className="group-foot">Opens Nextdoor's post composer with the details filled in. You review it and post there — nothing is sent automatically, and the photo is not included.</div>

          <div className="group">
            {h.shared ? <>
              <div className="cell" style={{ color: "var(--teal)" }}><BadgeCheck size={18} /> Filed with the public works relay</div>
              <div className="cell"><span>Ticket</span><span className="val">{h.id.slice(0, 8)}</span></div>
            </> : guest ? (
              <div className="cell muted small"><Building2 size={18} /> Create an account to send reports to public works.</div>
            ) : (
              <button className="cell link" disabled={forwarding} onClick={() => {
                setForwarding(true);
                store.relay(h).then(id => { close(); nav.dialog({ title: "Sent to public works", message: `Ticket ${id.slice(0, 8)}. It's now on the shared map for everyone.`, actions: [{ label: "OK" }] }); })
                  .catch(e => nav.dialog({ title: "Couldn't reach the relay", message: `${(e as Error).message} The report is still saved on this device.`, actions: [{ label: "OK" }] }))
                  .finally(() => setForwarding(false));
              }}><Building2 size={18} /> {forwarding ? "Sending…" : "Send to public works relay"}</button>
            )}
          </div>
          <div className="group-foot">Files this report with the StormWatch backend over Open311. Towns that have opted in receive it at their public works desk; every report joins the open GIS feed. The photo is not sent.</div>

          {isLifeSafetyRisk(h.reportType, h.utilityLinesInvolved) && h.status !== "RESOLVED" && (
            <>
              <div className="group-head">Also</div>
              <div className="group">
                <a className="cell link" href="https://nj.pseg.com/outageandgasleaks" target="_blank" rel="noreferrer"><Globe size={18} /> PSE&amp;G outage &amp; downed wire page</a>
                <a className="cell link" href="sms:47734&body=OUT"><MessageSquare size={18} /> My own power is out — text OUT to PSE&amp;G</a>
              </div>
              <div className="group-foot">Texting OUT reports an outage at the address on your own PSE&amp;G account, and only from a phone enrolled by texting REG to 47734. It does not report this wire — call for that.</div>
            </>
          )}

          <div className="group-head">Still there?</div>
          <div className="group">
            <button className="cell link" onClick={() => store.confirmHazard(h)}><ThumbsUp size={18} /> Confirm this hazard</button>
            {(!h.shared || township) && (
              <label className="cell"><span>Crew status</span>
                <select className="val" style={{ border: 0, background: "none", color: "var(--teal)" }} value={h.status} disabled={busy}
                        onChange={e => act(() => store.setStatus(h, e.target.value as ReportStatus))}>
                  {REPORT_STATUSES.map(s => <option key={s} value={s}>{statusLabel[s]}</option>)}
                </select>
              </label>
            )}
          </div>

          <div className="group-head">Gone?</div>
          <div className="group">
            {!h.shared || canRemoveShared ? (
              <button className="cell" style={{ color: "var(--red)" }} disabled={busy} onClick={() => act(() => store.remove(h), close)}>
                <Trash2 size={18} /> {h.shared ? "Remove for everyone" : "Remove report"}
              </button>
            ) : guest ? (
              <div className="cell muted small">Create an account to vote that a hazard is gone.</div>
            ) : (
              <>
                <button className="cell link" disabled={busy || h.iVotedNotThere}
                        onClick={() => act(() => store.voteNotThere(h).then(removed => { if (removed) close(); }))}>
                  {h.iVotedNotThere ? <CircleCheck size={18} /> : <EyeOff size={18} />}
                  <span style={{ color: h.iVotedNotThere ? "var(--text)" : undefined }}>{h.iVotedNotThere ? "You said it's gone" : "It's not there anymore"}</span>
                </button>
                <div className="cell"><span>Said gone</span><span className="val" style={{ color: (h.notThereVotes ?? 0) > 0 ? "var(--orange)" : undefined }}>{h.notThereVotes ?? 0} of 3</span></div>
              </>
            )}
          </div>
          <div className="group-foot">
            {!h.shared ? "This report only exists on this device."
              : h.isMine ? "You reported this, so you can take it down. It comes off the map for everyone."
              : township ? "As township staff you can take this down once it is cleared. It comes off the map for everyone."
              : tooFar && !h.iVotedNotThere ? `You're ${voteMiles!.toFixed(1)} miles away. Votes count only from within 1 mile, so the people saying it's gone have seen the spot. ${EXPIRY_NOTE}`
              : `When 3 different people within 1 mile say a hazard is gone, it comes off the map for everyone. ${EXPIRY_NOTE}`}
          </div>
        </div>
      </div>
    </>
  );
}
