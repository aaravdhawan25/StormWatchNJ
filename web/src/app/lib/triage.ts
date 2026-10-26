import { functionURL, SUPABASE_KEY } from "./config";
import type { HazardType, RoadStatus, Severity } from "./models";

export interface Analysis {
  hazardType: HazardType; severity: Severity; roadStatus: RoadStatus; utilityLines: boolean;
  description: string; engine: string; evidence: string[]; confidence?: number;
}

// OpenAI photo analysis through the analyze-image function
export async function analyzeWithOpenAI(photo: Blob, token?: string): Promise<Analysis> {
  const form = new FormData();
  form.append("file", photo, "incident.jpg");
  const res = await fetch(functionURL("analyze-image"), {
    method: "POST", body: form,
    headers: token ? { apikey: SUPABASE_KEY, Authorization: `Bearer ${token}` } : { apikey: SUPABASE_KEY, "x-stormwatch-guest": "1" },
    signal: AbortSignal.timeout(30000),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.detail ?? "AI analysis failed.");
  return {
    hazardType: body.hazard_type, severity: body.severity, roadStatus: body.road_status,
    utilityLines: body.utility_lines_involved, description: body.suggested_description,
    engine: "OpenAI vision",
    evidence: ["Analyzed by an OpenAI vision model", "The photo was sent to OpenAI for this analysis"],
  };
}

// colour analysis, ported from the iPhone app's ImageSignals
export async function analyzeOnDevice(photo: Blob, town: string): Promise<Analysis> {
  const bitmap = await createImageBitmap(photo);
  const grid = 64;
  const canvas = document.createElement("canvas");
  canvas.width = grid; canvas.height = grid;
  const ctx = canvas.getContext("2d")!;
  ctx.drawImage(bitmap, 0, 0, grid, grid);
  const px = ctx.getImageData(0, 0, grid, grid).data;

  let water = 0, lower = 0, foliage = 0;
  for (let y = 0; y < grid; y++) for (let x = 0; x < grid; x++) {
    const i = (y * grid + x) * 4;
    const [h, s, b] = hsb(px[i] / 255, px[i + 1] / 255, px[i + 2] / 255);
    if (h >= 60 && h <= 165 && s > 0.18 && b > 0.06 && b < 0.85) foliage++;
    if (y >= (grid * 2) / 5) { lower++; water += waterWeight(h, s, b); }
  }
  const waterCoverage = water / lower, foliageCoverage = foliage / (grid * grid);

  const flood = waterCoverage * 1.6, tree = foliageCoverage * 1.0;
  const drain = waterCoverage > 0.12 && waterCoverage < 0.34 && foliageCoverage < 0.25 ? 0.22 : 0;
  const ranked: [HazardType, number][] = ([["DOWNED_TREE", tree], ["STREET_FLOODING", flood], ["CLOGGED_DRAIN", drain]] as [HazardType, number][])
    .sort((a, b) => b[1] - a[1]);
  const hazardType: HazardType = ranked[0][1] >= 0.3 ? ranked[0][0] : "OTHER";
  const confidence = Math.min(ranked[0][1] / 1.8, 0.8);

  let severity: Severity = "LOW";
  if (hazardType === "STREET_FLOODING") severity = waterCoverage > 0.55 ? "IMPASSABLE" : waterCoverage > 0.28 ? "MODERATE" : "LOW";
  else if (hazardType === "DOWNED_TREE") severity = confidence > 0.5 || foliageCoverage > 0.35 ? "IMPASSABLE" : "MODERATE";
  else if (hazardType === "CLOGGED_DRAIN") severity = "MODERATE";
  const roadStatus: RoadStatus = severity === "IMPASSABLE" ? "IMPASSABLE" : severity === "MODERATE" ? "ONE_LANE_OPEN" : "CLEAR_TO_PASS";

  const evidence: string[] = [];
  if (waterCoverage > 0.08) evidence.push(`Water-toned surface across ${Math.round(waterCoverage * 100)}% of the lower frame`);
  if (foliageCoverage > 0.1) evidence.push(`Vegetation across ${Math.round(foliageCoverage * 100)}% of the frame`);
  evidence.push("Colour analysis in the browser — no photo leaves this device");
  return { hazardType, severity, roadStatus, utilityLines: false, confidence, engine: "On-device analysis", evidence,
           description: describe(hazardType, roadStatus, false, town) };
}

export function describe(t: HazardType, road: RoadStatus, wires: boolean, town: string): string {
  const lead: Record<HazardType, string> = {
    STREET_FLOODING: `Standing water across the roadway in ${town}.`,
    DOWNED_TREE: `Fallen tree obstructing the roadway in ${town}.`,
    DOWNED_WIRE: `Downed utility line reported in ${town}.`,
    CLOGGED_DRAIN: `Storm drain blocked by debris in ${town}, water pooling at the curb.`,
    OTHER: `Storm-related road obstruction reported in ${town}.`,
  };
  const roadText: Record<RoadStatus, string> = {
    IMPASSABLE: " The road is impassable.", ONE_LANE_OPEN: " One lane is open; pass with care.", CLEAR_TO_PASS: " Passable with caution.",
  };
  return lead[t] + roadText[road] + (wires ? " Possible energized wires — treat as a live electrical hazard and dispatch the utility." : "");
}

function waterWeight(h: number, s: number, b: number) {
  if (b <= 0.08 || b >= 0.82) return 0;
  if (s >= 0.06 && s < 0.42 && h >= 170 && h <= 260) return 1;
  if (s >= 0.12 && s < 0.55 && h >= 15 && h <= 50 && b < 0.62) return 1;
  if (s < 0.06) return 0.35;
  return 0;
}

function hsb(r: number, g: number, b: number): [number, number, number] {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d > 0.0001) {
    if (max === r) h = 60 * (((g - b) / d) % 6);
    else if (max === g) h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  return [h, max <= 0.0001 ? 0 : d / max, max];
}
