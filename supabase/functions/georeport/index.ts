// Open311 GeoReport v2 for StormWatch NJ.
//
//   GET  /georeport/discovery.json
//   GET  /georeport/services.json
//   GET  /georeport/services/{service_code}.json
//   GET  /georeport/requests.json?status=open|closed&service_code=A,B&start_date=&end_date=
//   GET  /georeport/requests/{service_request_id}.json
//   POST /georeport/requests.json            (application/x-www-form-urlencoded)
//
// Spec: https://wiki.open311.org/GeoReport_v2/
//
// Reads are public. A POST must come from a signed-in StormWatch user (the app
// sends their session token) or carry an `api_key` listed in the
// OPEN311_API_KEYS secret, for a town's own system. With neither it is refused,
// so this cannot be used to flood the map anonymously.
//
// Narrower than the spec: JSON only; `lat`/`long` are required (there is no
// geocoder to place an `address_string`); and reporter name, email and phone
// are accepted and discarded, so the public feed cannot leak who filed a report.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const AGENCY = "StormWatch NJ Civic Network";
const SERVICES: Record<string, [string, string, string]> = {
  CLOGGED_DRAIN: ["Clogged Storm Drain", "Catch basin or storm drain blocked, water ponding at the curb.", "Stormwater"],
  STREET_FLOODING: ["Street Flooding", "Standing or moving water across a roadway.", "Stormwater"],
  DOWNED_TREE: ["Downed Tree", "Tree or large limb obstructing a road or sidewalk.", "Roads"],
  DOWNED_WIRE: ["Downed Wire", "Utility line down. Callers should also dial 911 and the utility.", "Utilities"],
  OTHER: ["Other Storm Hazard", "Storm-related obstruction not covered above.", "Roads"],
};
const SEVERITIES = ["LOW", "MODERATE", "IMPASSABLE"];
const ROAD_STATUSES = ["CLEAR_TO_PASS", "ONE_LANE_OPEN", "IMPASSABLE"];
const PUBLIC_COLUMNS =
  "id, report_type, severity, road_status, utility_lines_involved, description, municipality, address, zipcode, latitude, longitude, status, upvotes, created_at, updated_at";

const title = (s: string) => s.toLowerCase().replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

const ATTRIBUTES = [
  { variable: true, code: "severity", datatype: "singlevaluelist", required: false, datatype_description: null, order: 1,
    description: "How bad is it?", values: SEVERITIES.map((s) => ({ key: s, name: title(s) })) },
  { variable: true, code: "road_status", datatype: "singlevaluelist", required: false, datatype_description: null, order: 2,
    description: "Can traffic get through?", values: ROAD_STATUSES.map((s) => ({ key: s, name: title(s) })) },
  { variable: true, code: "utility_lines_involved", datatype: "singlevaluelist", required: false, datatype_description: null, order: 3,
    description: "Are utility lines down or tangled in it?", values: [{ key: "true", name: "Yes" }, { key: "false", name: "No" }] },
  { variable: true, code: "municipality", datatype: "string", required: false, datatype_description: "Town name", order: 4,
    description: "Municipality", values: [] },
  { variable: true, code: "zipcode", datatype: "string", required: false, datatype_description: "5-digit ZIP", order: 5,
    description: "ZIP code, used to route the report to the right public works desk.", values: [] },
];

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type" };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
// Open311's error shape: a list of {code, description}.
const fail = (status: number, description: string) => json([{ code: status, description }], status);

// deno-lint-ignore no-explicit-any
function toOpen311(h: any) {
  return {
    service_request_id: h.id,
    status: h.status === "RESOLVED" ? "closed" : "open",
    status_notes: ({ ACTIVE: "Reported", IN_PROGRESS: "Crew assigned", RESOLVED: "Resolved" } as Record<string, string>)[h.status],
    service_name: (SERVICES[h.report_type] ?? SERVICES.OTHER)[0],
    service_code: h.report_type,
    description: h.description,
    agency_responsible: AGENCY,
    service_notice: "Unverified resident report, triaged by software.",
    requested_datetime: h.created_at,
    updated_datetime: h.updated_at,
    expected_datetime: null,
    address: h.address,
    address_id: null,
    zipcode: h.zipcode,
    lat: h.latitude,
    long: h.longitude,
    media_url: null,
  };
}

const mapsLink = (lat: number, lon: number) => `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;

/** Forwards one new report to its town's public works desk, if that town opted in. Never throws. */
async function dispatch(admin: SupabaseClient, id: string) {
  try {
    const { data: h } = await admin.from("hazards").select(PUBLIC_COLUMNS).eq("id", id).maybeSingle();
    if (!h?.zipcode) return;
    const { data: town } = await admin.from("dispatch_towns").select("*").eq("zipcode", h.zipcode).eq("enabled", true).maybeSingle();
    if (!town) return;

    // Cap what any one desk receives in an hour.
    const cap = Number(Deno.env.get("DISPATCH_MAX_PER_HOUR") ?? "20");
    const since = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await admin.from("hazards").select("id", { count: "exact", head: true })
      .eq("zipcode", h.zipcode).gte("dispatched_at", since);
    if ((count ?? 0) >= cap) return;

    const card = {
      source: AGENCY,
      ticket_id: h.id,
      ticket_type: h.report_type,
      severity: h.severity,
      road_status: h.road_status,
      utility_lines_involved: h.utility_lines_involved,
      description: h.description,
      address: h.address,
      municipality: h.municipality,
      zipcode: h.zipcode,
      latitude: h.latitude,
      longitude: h.longitude,
      coordinates: `${h.latitude},${h.longitude}`,
      map_url: mapsLink(h.latitude, h.longitude),
      photo: null,
      confirmations: h.upvotes,
      reported_at: h.created_at,
      // Said plainly so a dispatcher weighs it correctly.
      verification: "Unverified resident report, triaged by software. Confirm on site.",
    };

    let sent = false;
    if (town.webhook_url) {
      const r = await fetch(town.webhook_url, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(card),
        signal: AbortSignal.timeout(10_000),
      });
      sent = r.ok || sent;
    }
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("DISPATCH_FROM_EMAIL");
    if (town.email && resendKey && from) {
      const lines = [
        `${title(card.ticket_type)} — ${card.severity}`, "", card.description, "",
        `Road status: ${title(card.road_status).toLowerCase()}`,
        `Location: ${card.address ?? card.municipality ?? "see coordinates"}`,
        `GPS: ${card.coordinates}`, `Map: ${card.map_url}`,
        `Confirmations: ${card.confirmations}`, `Reported: ${card.reported_at}`,
        ...(card.utility_lines_involved ? ["", "UTILITY LINES INVOLVED — treat as energized; utility must clear before crews approach."] : []),
        "", card.verification, `Ticket ${card.ticket_id} · StormWatch NJ`,
      ];
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from, to: [town.email], subject: `[StormWatch NJ] ${title(card.ticket_type)} — ${card.severity}`, text: lines.join("\n") }),
        signal: AbortSignal.timeout(10_000),
      });
      sent = r.ok || sent;
    }
    if (sent) await admin.from("hazards").update({ dispatched_at: new Date().toISOString() }).eq("id", id);
  } catch (error) {
    console.error("dispatch failed", id, error);
  }
}

async function createRequest(req: Request, admin: SupabaseClient) {
  const form = await req.formData();
  const field = (k: string) => (form.get(k)?.toString() ?? "").trim();

  // Who is asking: a signed-in user, or a town system holding an API key.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  let client: SupabaseClient | null = null;
  if (token && token !== ANON_KEY) {
    const { data } = await admin.auth.getUser(token);
    if (data?.user) {
      client = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: `Bearer ${token}` } } });
    }
  }
  if (!client) {
    const keys = (Deno.env.get("OPEN311_API_KEYS") ?? "").split(",").map((k) => k.trim()).filter(Boolean);
    if (!field("api_key") || !keys.includes(field("api_key"))) return fail(403, "Sign in, or supply a valid api_key.");
    client = admin;
  }

  const code = field("service_code");
  if (!code) return fail(400, "service_code is required.");
  if (!SERVICES[code]) return fail(404, `service_code '${code}' was not found.`);

  const lat = Number(field("lat")), lon = Number(field("long"));
  if (!field("lat") || !field("long") || Number.isNaN(lat) || Number.isNaN(lon)) {
    return fail(400, "lat and long are required and must be numbers. address_string alone cannot be placed on the map.");
  }
  const severity = field("attribute[severity]") || "MODERATE";
  const roadStatus = field("attribute[road_status]") || "ONE_LANE_OPEN";
  if (!SEVERITIES.includes(severity)) return fail(400, `attribute[severity] must be one of ${SEVERITIES.join(", ")}.`);
  if (!ROAD_STATUSES.includes(roadStatus)) return fail(400, `attribute[road_status] must be one of ${ROAD_STATUSES.join(", ")}.`);

  const description = field("description") || SERVICES[code][0];
  if (description.length > 4000) return fail(400, "description must be 4000 characters or fewer.");

  const address = field("address_string");
  const zipcode = field("attribute[zipcode]") || (address.match(/\b0[78]\d{3}\b/)?.[0] ?? "");

  const { data, error } = await client.rpc("report_hazard", {
    p_report_type: code, p_severity: severity, p_road_status: roadStatus,
    p_utility_lines_involved: field("attribute[utility_lines_involved]").toLowerCase() === "true",
    p_description: description, p_latitude: lat, p_longitude: lon,
    p_address: address || null, p_zipcode: zipcode || null, p_municipality: field("attribute[municipality]") || null,
  });
  if (error) {
    // P0001 is a rule the database refused on purpose, e.g. outside New Jersey.
    return error.code === "P0001" ? fail(400, error.message) : fail(500, "Could not store the report.");
  }

  if (!data.duplicate) {
    // Runs after the response so a slow town endpoint never stalls the app.
    const job = dispatch(admin, data.id);
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(job);
  }
  return json([{
    service_request_id: data.id,
    service_notice: data.duplicate
      ? "Matched an open report nearby; recorded as a confirmation."
      : "Received. Forwarded to public works where the town has opted in.",
    account_id: null,
  }], 201);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  const url = new URL(req.url);
  const path = url.pathname.replace(/^.*\/georeport/, "") || "/";
  const admin = createClient(SUPABASE_URL, SERVICE_KEY);

  try {
    if (req.method === "POST" && path === "/requests.json") return await createRequest(req, admin);
    if (req.method !== "GET") return fail(405, "Method not allowed.");

    if (path === "/discovery.json") {
      return json({
        changeset: "2026-10-10T00:00:00+00:00",
        contact: "See the project README.",
        key_service: "POST requires a signed-in StormWatch NJ user or an api_key issued to a municipality.",
        endpoints: [{
          specification: "http://wiki.open311.org/GeoReport_v2",
          url: `${SUPABASE_URL}/functions/v1/georeport`,
          changeset: "2026-10-10T00:00:00+00:00", type: "production", formats: ["application/json"],
        }],
      });
    }
    if (path === "/services.json") {
      return json(Object.entries(SERVICES).map(([code, [name, description, group]]) => ({
        service_code: code, service_name: name, description, metadata: true, type: "realtime",
        keywords: code.toLowerCase().replace(/_/g, ","), group,
      })));
    }
    const service = path.match(/^\/services\/([A-Z_]+)\.json$/);
    if (service) {
      return SERVICES[service[1]] ? json({ service_code: service[1], attributes: ATTRIBUTES })
        : fail(404, `service_code '${service[1]}' was not found.`);
    }
    if (path === "/requests.json") {
      const q = url.searchParams;
      const status = q.get("status");
      if (status && !["open", "closed"].includes(status)) return fail(400, "status must be 'open' or 'closed'.");
      let query = admin.from("hazards").select(PUBLIC_COLUMNS).order("created_at", { ascending: false }).limit(1000);
      if (status === "open") query = query.neq("status", "RESOLVED");
      if (status === "closed") query = query.eq("status", "RESOLVED");
      const ids = (q.get("service_request_id") ?? "").split(",").filter(Boolean);
      if (ids.some((i) => !/^[0-9a-f-]{36}$/i.test(i))) return json([]);
      if (ids.length) query = query.in("id", ids);
      const codes = (q.get("service_code") ?? "").split(",").filter(Boolean);
      if (codes.length) query = query.in("report_type", codes);
      for (const [param, op] of [["start_date", "gte"], ["end_date", "lte"]] as const) {
        const value = q.get(param);
        if (!value) continue;
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return fail(400, "start_date and end_date must be ISO 8601 datetimes.");
        query = op === "gte" ? query.gte("created_at", date.toISOString()) : query.lte("created_at", date.toISOString());
      }
      const { data, error } = await query;
      if (error) return fail(500, "Could not read reports.");
      return json(data.map(toOpen311));
    }
    const one = path.match(/^\/requests\/([0-9a-f-]{36})\.json$/i);
    if (one) {
      const { data } = await admin.from("hazards").select(PUBLIC_COLUMNS).eq("id", one[1]).maybeSingle();
      return data ? json([toOpen311(data)]) : fail(404, `service_request_id '${one[1]}' was not found.`);
    }
    return fail(404, "Not found.");
  } catch (error) {
    console.error(error);
    return fail(400, "The request could not be processed.");
  }
});
