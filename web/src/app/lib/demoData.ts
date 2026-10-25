import type { Hazard, HazardType, RoadStatus, Severity } from "./models";

// Fictional sample data, the same set the iPhone app seeds. Not real incidents.
function make(id: string, t: HazardType, s: Severity, r: RoadStatus, wires: boolean, details: string,
              lat: number, lon: number, town: string, status: Hazard["status"], upvotes: number, agoSec: number,
              simulated = false): Hazard {
  const at = new Date(Date.now() - agoSec * 1000).toISOString();
  return { id, reportType: t, severity: s, roadStatus: r, utilityLinesInvolved: wires, details, latitude: lat, longitude: lon,
           municipality: town, status, upvotes, createdAt: at, updatedAt: at, shared: false, simulated };
}

export const seedHazards = (): Hazard[] => [
  make("demo-1", "STREET_FLOODING", "IMPASSABLE", "IMPASSABLE", false,
       "Scudders Mill Road underpass is holding roughly two feet of water. Two vehicles already turned around.",
       40.3395, -74.5751, "Plainsboro", "ACTIVE", 14, 3100),
  make("demo-2", "DOWNED_TREE", "IMPASSABLE", "ONE_LANE_OPEN", true,
       "Large oak down across Canal Road with the primary line caught in the crown. Treat wires as energized.",
       40.4512, -74.5808, "Franklin Township", "IN_PROGRESS", 9, 7400),
  make("demo-3", "CLOGGED_DRAIN", "MODERATE", "ONE_LANE_OPEN", false,
       "Catch basin at Dey Road and Plainsboro Road packed with leaf litter; curb lane is ponding.",
       40.3216, -74.5612, "Plainsboro", "ACTIVE", 5, 11000),
  make("demo-4", "STREET_FLOODING", "MODERATE", "ONE_LANE_OPEN", false,
       "Millstone River backing over the shoulder near the towpath lot. Passable slowly in the left lane.",
       40.429, -74.6015, "Princeton", "ACTIVE", 7, 15600),
  make("demo-5", "DOWNED_WIRE", "IMPASSABLE", "IMPASSABLE", true,
       "Service drop down across the sidewalk on Harrison Street. Utility notified, road closed at both ends.",
       40.3521, -74.6402, "Princeton", "ACTIVE", 21, 2400),
  make("demo-6", "DOWNED_TREE", "LOW", "CLEAR_TO_PASS", false,
       "Limbs down in the bike lane on Route 27 near the canal bridge. Cars unaffected.",
       40.3982, -74.5395, "South Brunswick", "RESOLVED", 3, 86400),
];

export const stormSurgeHazards = (): Hazard[] => [
  make("sim-1", "STREET_FLOODING", "IMPASSABLE", "IMPASSABLE", false,
       "SIMULATED: Raritan overtopping Talmage Avenue. Full closure, water over the centerline.", 40.5652, -74.5389, "Bound Brook", "ACTIVE", 18, 0, true),
  make("sim-2", "DOWNED_TREE", "IMPASSABLE", "IMPASSABLE", true,
       "SIMULATED: Two trees down with wires across Main Street. Utility crew required before clearing.", 40.5388, -74.5901, "Manville", "ACTIVE", 11, 420, true),
  make("sim-3", "CLOGGED_DRAIN", "MODERATE", "ONE_LANE_OPEN", false,
       "SIMULATED: Basin surcharging at Washington Ave, water backing into the intersection.", 40.4894, -74.4467, "New Brunswick", "ACTIVE", 6, 840, true),
  make("sim-4", "STREET_FLOODING", "IMPASSABLE", "IMPASSABLE", false,
       "SIMULATED: Nine-foot crest on the Millstone. River Road closed between the locks.", 40.458, -74.596, "Franklin Township", "ACTIVE", 24, 1260, true),
  make("sim-5", "DOWNED_WIRE", "IMPASSABLE", "IMPASSABLE", true,
       "SIMULATED: Primary conductor down and arcing near the substation approach road.", 40.3701, -74.6205, "West Windsor", "ACTIVE", 9, 1680, true),
];

const TOWNS: [string, number, number][] = [
  ["Plainsboro", 40.3318, -74.5893], ["Princeton", 40.3573, -74.6672], ["West Windsor", 40.2965, -74.6221],
  ["South Brunswick", 40.3868, -74.5232], ["New Brunswick", 40.4862, -74.4518], ["Franklin Township", 40.4976, -74.5321],
  ["Bound Brook", 40.5679, -74.5385], ["Manville", 40.5401, -74.5885], ["Hillsborough", 40.4665, -74.6482],
  ["Edison", 40.5187, -74.4121], ["Morristown", 40.7968, -74.4815], ["Chatham", 40.7407, -74.3838],
  ["Little Falls", 40.869, -74.2082], ["Lodi", 40.8823, -74.0832], ["High Bridge", 40.6684, -74.8954],
  ["Pemberton", 39.9718, -74.6829], ["Squankum", 40.159, -74.1329],
];

/** Nearest town in a small offline list, as the iPhone app does. */
/** The nearest town in the list, but only if it is close by (about 8 miles):
 *  the list covers central NJ, so elsewhere it would name the wrong town. */
export function nearbyTown(p: { latitude: number; longitude: number }): string | null {
  const name = nearestTown(p);
  const t = TOWNS.find(x => x[0] === name)!;
  const miles = Math.hypot((t[1] - p.latitude) * 69, (t[2] - p.longitude) * 53);
  return miles <= 8 ? name : null;
}

export function nearestTown(p: { latitude: number; longitude: number }): string {
  let best = TOWNS[0], bestD = Infinity;
  for (const t of TOWNS) {
    const d = (t[1] - p.latitude) ** 2 + (t[2] - p.longitude) ** 2;
    if (d < bestD) { bestD = d; best = t; }
  }
  return best[0];
}
