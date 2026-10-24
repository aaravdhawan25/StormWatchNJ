import type { Hazard } from "./models";
import { hazardLabel, milesBetween } from "./models";
import type { FloodAlert } from "./publicData";

// The iPhone app's notification rules, for the browser. Three kinds: a flood
// alert where you are; an impassable hazard or downed wire inside your radius;
// a change to a report you filed. The browser shows them while the site is
// open (including in a background tab). On iPhone, Safari only allows web
// notifications for sites added to the Home Screen.

export interface NotifyPrefs { flood: boolean; nearby: boolean; mine: boolean }
interface State { account?: string; known: string[]; mine: Record<string, string>; alerts: string[] }

const PREFS = "stormwatch-web-notify-prefs";
const STATE = "stormwatch-web-notify-state";

export const notificationsSupported = () => typeof window !== "undefined" && "Notification" in window;
export const permission = (): NotificationPermission | "unsupported" => notificationsSupported() ? Notification.permission : "unsupported";

export function loadPrefs(): NotifyPrefs {
  try { return { flood: true, nearby: true, mine: true, ...JSON.parse(localStorage.getItem(PREFS) ?? "{}") }; }
  catch { return { flood: true, nearby: true, mine: true }; }
}
export const savePrefs = (p: NotifyPrefs) => localStorage.setItem(PREFS, JSON.stringify(p));

const load = (): State => { try { return { known: [], mine: {}, alerts: [], ...JSON.parse(localStorage.getItem(STATE) ?? "{}") }; } catch { return { known: [], mine: {}, alerts: [] }; } };
const save = (s: State) => localStorage.setItem(STATE, JSON.stringify(s));

export async function requestPermission() {
  if (!notificationsSupported()) return "unsupported" as const;
  return Notification.requestPermission();
}

async function send(id: string, title: string, body: string, tab: "nearby" | "alerts") {
  if (permission() !== "granted") return;
  const options = { body, tag: id, icon: "/icon-192.png", badge: "/icon-192.png", data: { tab } };
  const reg = await navigator.serviceWorker?.getRegistration();
  if (reg) { await reg.showNotification(title, options); return; }
  const n = new Notification(title, options);
  n.onclick = () => { window.focus(); window.dispatchEvent(new CustomEvent("stormwatch-open-tab", { detail: tab })); };
}

/** Compares the shared hazard list with the last one seen. */
export function processHazards(shared: Hazard[], accountId: string, here: { latitude: number; longitude: number },
                               radius: number, prefs: NotifyPrefs) {
  const state = load();
  const ids = shared.map(h => h.id);
  const mine = Object.fromEntries(shared.filter(h => h.isMine).map(h => [h.id, h.status]));

  // First look for this account in this browser: remember the map, announce nothing.
  if (state.account !== accountId) { save({ ...state, account: accountId, known: ids, mine }); return; }

  if (prefs.nearby) {
    for (const h of shared) {
      if (state.known.includes(h.id) || h.isMine || h.status === "RESOLVED") continue;
      if (h.severity !== "IMPASSABLE" && !h.utilityLinesInvolved) continue;
      const miles = milesBetween(here, h);
      if (miles > radius) continue;
      send(`hazard-${h.id}`, h.utilityLinesInvolved ? `⚡️ ${hazardLabel[h.reportType]} with wires nearby` : `${hazardLabel[h.reportType]} nearby`,
           `${miles.toFixed(1)} mi away in ${h.municipality}. ${h.details}`, "nearby");
    }
  }
  if (prefs.mine) {
    for (const [id, status] of Object.entries(mine)) {
      const before = state.mine[id];
      if (!before || before === status) continue;
      if (status === "IN_PROGRESS") send(`mine-${id}-crew`, "A crew is on the way", "Public works marked your report as in progress.", "nearby");
      if (status === "RESOLVED") send(`mine-${id}-resolved`, "Your report was resolved", "Public works marked the hazard you reported as cleared.", "nearby");
    }
    for (const id of Object.keys(state.mine)) {
      if (!ids.includes(id)) send(`mine-${id}-removed`, "Your report came off the map", "Neighbors or your township marked it as gone, or it expired after 3 days without an update.", "nearby");
    }
  }
  save({ ...state, known: ids, mine });
}

/** Call when the person removes their own report, so they aren't told it "came off the map". */
export function forgetMine(id: string) {
  const s = load(); delete s.mine[id]; save(s);
}

export function processAlerts(alerts: FloodAlert[], prefs: NotifyPrefs) {
  if (!prefs.flood) return;
  const s = load();
  for (const a of alerts) {
    if (!a.live || s.alerts.includes(a.id)) continue;
    const until = a.expires ? ` · until ${new Date(a.expires).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}` : "";
    send(`flood-${a.id}`, `${a.event} in effect`, a.area + until, "alerts");
    s.alerts.push(a.id);
  }
  save({ ...s, alerts: s.alerts.slice(-200) });
}

export const resetNotifications = () => localStorage.removeItem(STATE);
