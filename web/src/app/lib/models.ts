// Mirrors StormWatchNJ/Models in the iPhone app.

export type HazardType = "CLOGGED_DRAIN" | "STREET_FLOODING" | "DOWNED_TREE" | "DOWNED_WIRE" | "OTHER";
export type Severity = "LOW" | "MODERATE" | "IMPASSABLE";
export type RoadStatus = "CLEAR_TO_PASS" | "ONE_LANE_OPEN" | "IMPASSABLE";
export type ReportStatus = "ACTIVE" | "IN_PROGRESS" | "RESOLVED";

export interface Hazard {
  /** Server id for shared hazards; a local id for demo and guest reports. */
  id: string;
  reportType: HazardType;
  severity: Severity;
  roadStatus: RoadStatus;
  utilityLinesInvolved: boolean;
  details: string;
  latitude: number;
  longitude: number;
  municipality: string;
  address?: string | null;
  zipcode?: string | null;
  status: ReportStatus;
  upvotes: number;
  createdAt: string;
  updatedAt: string;
  /** True when it lives in the shared database (voting and removal go there). */
  shared: boolean;
  isMine?: boolean;
  notThereVotes?: number;
  iVotedNotThere?: boolean;
  /** Object URL of a photo taken in this browser session, never uploaded. */
  photoURL?: string;
  simulated?: boolean;
}

export const HAZARD_TYPES: HazardType[] = ["CLOGGED_DRAIN", "STREET_FLOODING", "DOWNED_TREE", "DOWNED_WIRE", "OTHER"];
export const SEVERITIES: Severity[] = ["LOW", "MODERATE", "IMPASSABLE"];
export const ROAD_STATUSES: RoadStatus[] = ["CLEAR_TO_PASS", "ONE_LANE_OPEN", "IMPASSABLE"];
export const REPORT_STATUSES: ReportStatus[] = ["ACTIVE", "IN_PROGRESS", "RESOLVED"];

export const hazardLabel: Record<HazardType, string> = {
  CLOGGED_DRAIN: "Clogged Storm Drain",
  STREET_FLOODING: "Street Flooding",
  DOWNED_TREE: "Downed Tree",
  DOWNED_WIRE: "Downed Wire",
  OTHER: "Other Hazard",
};

export const hazardShort: Record<HazardType, string> = {
  CLOGGED_DRAIN: "Drains", STREET_FLOODING: "Flooding", DOWNED_TREE: "Trees", DOWNED_WIRE: "Wires", OTHER: "Other",
};

/** Each hazard type has its own colour family, like the iPhone app. */
export const hazardGradient: Record<HazardType, [string, string]> = {
  STREET_FLOODING: ["#1f73db", "#24b8d6"],
  CLOGGED_DRAIN: ["#4d52c7", "#3d94db"],
  DOWNED_TREE: ["#1a8052", "#6bb84d"],
  DOWNED_WIRE: ["#db3d29", "#faa829"],
  OTHER: ["#5c617a", "#8f85b3"],
};

export const severityLabel: Record<Severity, string> = { LOW: "Low", MODERATE: "Moderate", IMPASSABLE: "Impassable" };
export const severityColor: Record<Severity, string> = { LOW: "#e6b800", MODERATE: "#ff9500", IMPASSABLE: "#ff3b30" };
export const severityWeight: Record<Severity, number> = { LOW: 0, MODERATE: 1, IMPASSABLE: 2 };

export const roadLabel: Record<RoadStatus, string> = {
  CLEAR_TO_PASS: "Clear to pass", ONE_LANE_OPEN: "One lane open", IMPASSABLE: "Impassable",
};
export const statusLabel: Record<ReportStatus, string> = {
  ACTIVE: "Active", IN_PROGRESS: "DPW en route", RESOLVED: "Resolved",
};

export const isLifeSafetyRisk = (type: HazardType, utilityLines: boolean) => utilityLines || type === "DOWNED_WIRE";

export function relativeTime(iso: string): string {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 60) return "just now";
  const units: [number, string][] = [[604800, "w"], [86400, "d"], [3600, "h"], [60, "m"]];
  for (const [size, unit] of units) if (seconds >= size) return `${Math.floor(seconds / size)}${unit} ago`;
  return "just now";
}

export function milesBetween(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude), dLon = toRad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return (2 * 6371000 * Math.asin(Math.sqrt(h))) / 1609.34;
}
