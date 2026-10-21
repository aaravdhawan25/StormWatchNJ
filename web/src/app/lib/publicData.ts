// Live public data — the same federal sources the iPhone app uses, called
// straight from the browser (all of them allow it).

// ---------- USGS river gauges ----------

export interface Station {
  siteID: string; name: string; county: string; latitude: number; longitude: number;
  /** Demo thresholds, as in the iPhone app — not official NWS flood stages. */
  actionStageFt: number; floodStageFt: number;
  heightFt?: number; readingTime?: string;
}

export const STATIONS: Station[] = [
  { siteID: "01402000", name: "Millstone River at Blackwells Mills", county: "Somerset", latitude: 40.475, longitude: -74.5758, actionStageFt: 5, floodStageFt: 7 },
  { siteID: "01400500", name: "Raritan River at Manville", county: "Somerset", latitude: 40.5556, longitude: -74.5828, actionStageFt: 8, floodStageFt: 10 },
  { siteID: "01403060", name: "Raritan River below Calco Dam at Bound Brook", county: "Somerset", latitude: 40.5511, longitude: -74.5483, actionStageFt: 22, floodStageFt: 28 },
  { siteID: "01396500", name: "South Branch Raritan River near High Bridge", county: "Hunterdon", latitude: 40.6778, longitude: -74.8792, actionStageFt: 5.5, floodStageFt: 8.5 },
  { siteID: "01379000", name: "Passaic River near Millington", county: "Morris", latitude: 40.68, longitude: -74.5289, actionStageFt: 6, floodStageFt: 8 },
  { siteID: "01389500", name: "Passaic River at Little Falls", county: "Passaic", latitude: 40.8847, longitude: -74.2261, actionStageFt: 5, floodStageFt: 7 },
  { siteID: "01391500", name: "Saddle River at Lodi", county: "Bergen", latitude: 40.8903, longitude: -74.0806, actionStageFt: 4, floodStageFt: 6 },
  { siteID: "01381500", name: "Whippany River at Morristown", county: "Morris", latitude: 40.8072, longitude: -74.4569, actionStageFt: 3.5, floodStageFt: 5 },
  { siteID: "01445500", name: "Pequest River at Pequest", county: "Warren", latitude: 40.8306, longitude: -74.9778, actionStageFt: 3.5, floodStageFt: 5 },
  { siteID: "01408000", name: "Manasquan River at Squankum", county: "Monmouth", latitude: 40.1614, longitude: -74.1547, actionStageFt: 4, floodStageFt: 6 },
  { siteID: "01467000", name: "North Branch Rancocas Creek at Pemberton", county: "Burlington", latitude: 39.97, longitude: -74.6844, actionStageFt: 3, floodStageFt: 4.5 },
];

export type GaugeAlert = "NORMAL" | "ACTION" | "FLOOD" | "MAJOR";
export function gaugeAlert(s: Station): GaugeAlert {
  if (s.heightFt == null) return "NORMAL";
  if (s.heightFt >= s.floodStageFt + 3) return "MAJOR";
  if (s.heightFt >= s.floodStageFt) return "FLOOD";
  if (s.heightFt >= s.actionStageFt) return "ACTION";
  return "NORMAL";
}
export const gaugeLabel: Record<GaugeAlert, string> = { NORMAL: "Normal", ACTION: "Action Stage", FLOOD: "Flood Stage", MAJOR: "Major Flooding" };
export const gaugeColor: Record<GaugeAlert, string> = { NORMAL: "#34c759", ACTION: "#e6b800", FLOOD: "#ff9500", MAJOR: "#ff3b30" };

export async function fetchGauges(): Promise<Station[]> {
  const url = `https://waterservices.usgs.gov/nwis/iv/?format=json&parameterCd=00065&siteStatus=active&sites=${STATIONS.map(s => s.siteID).join(",")}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error("USGS Water Services didn't answer.");
  const data = await res.json();
  const readings = new Map<string, { h: number; t: string; name: string }>();
  for (const ts of data.value.timeSeries) {
    const code = ts.sourceInfo.siteCode[0].value;
    const point = ts.values?.[0]?.value?.at(-1);
    const h = point ? Number(point.value) : NaN;
    // USGS uses -999999 as its "no data" sentinel.
    if (point && !Number.isNaN(h) && h > -900000) readings.set(code, { h, t: point.dateTime, name: ts.sourceInfo.siteName.replace(" NJ", "") });
  }
  return STATIONS.map(s => {
    const r = readings.get(s.siteID);
    return r ? { ...s, heightFt: r.h, readingTime: r.t, name: r.name } : s;
  });
}

// ---------- Flood alerts ----------

export interface FloodAlert {
  id: string; live: boolean; event: string; headline: string; severity: string; area: string;
  sender: string; sent?: string; expires?: string; details: string; instruction: string;
}

export const alertColor = (sev: string) =>
  ["extreme", "severe"].includes(sev.toLowerCase()) ? "#ff3b30" : sev.toLowerCase() === "moderate" ? "#ff9500" : "#e6b800";

const isFlood = (e: string) => e.toLowerCase().includes("flood");

/** In effect now, from the National Weather Service. */
export async function fetchLiveAlerts(lat: number, lon: number): Promise<FloodAlert[]> {
  const res = await fetch(`https://api.weather.gov/alerts/active?point=${lat.toFixed(4)},${lon.toFixed(4)}`,
                          { headers: { Accept: "application/geo+json" } });
  if (!res.ok) throw new Error("The National Weather Service didn't answer. Live alerts may be missing.");
  const data = await res.json();
  return (data.features ?? [])
    .map((f: { properties: Record<string, string> }) => f.properties)
    .filter((p: Record<string, string>) => isFlood(p.event) && p.status === "Actual" && p.messageType !== "Cancel")
    .map((p: Record<string, string>) => ({
      id: p.id, live: true, event: p.event, headline: p.headline ?? p.event, severity: p.severity ?? "Unknown",
      area: p.areaDesc ?? "", sender: p.senderName ?? "National Weather Service", sent: p.sent,
      expires: p.ends ?? p.expires, details: p.description ?? "", instruction: p.instruction ?? "",
    }));
}

export const HISTORY_DAYS = 90;

/** FEMA OpenFEMA IPAWS archive — published a day late on purpose, so history only. */
export async function fetchAlertHistory(lat: number, lon: number): Promise<FloodAlert[]> {
  const since = new Date(Date.now() - HISTORY_DAYS * 86400000).toISOString();
  const params = new URLSearchParams({
    $select: "identifier,sent,status,msgType,info",
    $orderby: "sent desc",
    $top: "100",
    $filter: `sent ge '${since}' and geo.intersects(searchGeometry, geography'POINT(${lon} ${lat})')`,
  });
  const res = await fetch(`https://www.fema.gov/api/open/v1/IpawsArchivedAlerts?${params}`);
  if (!res.ok) throw new Error("FEMA's alert archive didn't answer.");
  const rows = (await res.json()).IpawsArchivedAlerts ?? [];
  const seen = new Set<string>();
  const out: FloodAlert[] = [];
  for (const r of rows) {
    const info = r.info?.[0];
    if (r.status !== "Actual" || !["Alert", "Update"].includes(r.msgType) || !info || !isFlood(info.event)) continue;
    if (seen.has(r.identifier)) continue;
    seen.add(r.identifier);
    out.push({ id: r.identifier, live: false, event: info.event, headline: info.headline ?? info.event,
               severity: info.severity ?? "Unknown", area: info.area?.[0]?.areaDesc ?? "", sender: info.senderName ?? "",
               sent: r.sent, expires: info.expires, details: info.description ?? "", instruction: info.instruction ?? "" });
  }
  return out;
}

// ---------- Shelters ----------

export interface Shelter {
  id: string; name: string; address: string; organization?: string;
  pets?: boolean; accessible?: boolean; latitude?: number; longitude?: number; miles?: number;
}

export const SHELTER_RADIUS_MILES = 50;
export const FEMA_TEXT_NUMBER = "43362";

export async function fetchShelters(lat: number, lon: number): Promise<Shelter[]> {
  const params = new URLSearchParams({
    where: "shelter_status='OPEN'", geometry: `${lon},${lat}`, geometryType: "esriGeometryPoint", inSR: "4326",
    distance: String(SHELTER_RADIUS_MILES), units: "esriSRUnit_StatuteMile",
    outFields: "shelter_id,shelter_name,address,city,state,zip,org_name,pet_accommodations_code,wheelchair_accessible",
    returnGeometry: "true", outSR: "4326", f: "json",
  });
  const res = await fetch(`https://gis.fema.gov/arcgis/rest/services/NSS/OpenShelters/FeatureServer/0/query?${params}`);
  const data = res.ok ? await res.json() : null;
  if (!data || data.error) throw new Error("Couldn't reach FEMA's shelter list. Use the text option below.");
  const flag = (v: unknown, no: string[]) => {
    const t = typeof v === "string" ? v.toUpperCase() : "";
    return !t || t === "UNK" ? undefined : !no.includes(t);
  };
  return data.features.map((f: { attributes: Record<string, unknown>; geometry?: { x: number; y: number } }) => {
    const a = f.attributes;
    const zip = typeof a.zip === "string" && a.zip.length === 5 ? a.zip : undefined;
    const city = [a.city, a.state].filter(Boolean).join(", ");
    const shelter: Shelter = {
      id: String(a.shelter_id ?? Math.random()), name: String(a.shelter_name),
      address: [a.address, city, zip].filter(Boolean).join(", "),
      organization: (a.org_name as string) || undefined,
      pets: flag(a.pet_accommodations_code, ["NONE", "NO"]), accessible: flag(a.wheelchair_accessible, ["NO", "N"]),
      latitude: f.geometry?.y, longitude: f.geometry?.x,
    };
    if (shelter.latitude != null && shelter.longitude != null) {
      const toRad = (d: number) => (d * Math.PI) / 180;
      const h = Math.sin(toRad(shelter.latitude - lat) / 2) ** 2 +
        Math.cos(toRad(lat)) * Math.cos(toRad(shelter.latitude)) * Math.sin(toRad(shelter.longitude - lon) / 2) ** 2;
      shelter.miles = (2 * 6371000 * Math.asin(Math.sqrt(h))) / 1609.34;
    }
    return shelter;
  }).sort((x: Shelter, y: Shelter) => (x.miles ?? Infinity) - (y.miles ?? Infinity));
}

// ---------- Geocoding (OpenStreetMap Nominatim; Apple's geocoder is iOS-only) ----------

export interface Place { street?: string; city?: string; zip?: string; line?: string }

export async function reverseGeocode(lat: number, lon: number): Promise<Place | null> {
  try {
    const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&lat=${lat}&lon=${lon}`,
                            { signal: AbortSignal.timeout(6000) });
    const a = (await res.json()).address ?? {};
    const street = [a.house_number, a.road].filter(Boolean).join(" ") || undefined;
    const city = a.town ?? a.city ?? a.village ?? a.hamlet ?? a.township ?? a.county;
    const zip = typeof a.postcode === "string" ? a.postcode.slice(0, 5) : undefined;
    const parts = [street, city].filter(Boolean).join(", ");
    return { street, city, zip, line: parts ? `${parts}, NJ${zip ? " " + zip : ""}` : undefined };
  } catch {
    return null;
  }
}

export async function zipToPoint(zip: string): Promise<{ latitude: number; longitude: number } | null> {
  try {
    // Nominatim returns nothing when postalcode and state are combined, so search
    // by ZIP alone and check the answer is actually in New Jersey.
    const res = await fetch(`https://nominatim.openstreetmap.org/search?format=jsonv2&postalcode=${zip}&countrycodes=us&limit=1`,
                            { signal: AbortSignal.timeout(6000) });
    const hit = (await res.json())[0];
    if (!hit || !String(hit.display_name).includes("New Jersey")) return null;
    return { latitude: Number(hit.lat), longitude: Number(hit.lon) };
  } catch {
    return null;
  }
}
