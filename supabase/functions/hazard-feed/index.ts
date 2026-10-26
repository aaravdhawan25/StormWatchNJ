// open GIS layer of StormWatch NJ hazards, as RFC 7946 GeoJSON
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "GET") return new Response("Method not allowed", { status: 405, headers: CORS });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let query = admin.from("hazards")
    .select("id, report_type, severity, road_status, utility_lines_involved, description, municipality, address, zipcode, latitude, longitude, status, upvotes, created_at, updated_at")
    .order("created_at", { ascending: false }).limit(2000);
  if (new URL(req.url).searchParams.get("status") !== "all") query = query.neq("status", "RESOLVED");

  const { data, error } = await query;
  if (error) return new Response(JSON.stringify({ error: "Could not read hazards." }), { status: 500, headers: CORS });

  const collection = {
    type: "FeatureCollection",
    source: "StormWatch NJ",
    generated_at: new Date().toISOString(),
    features: data.map((h) => ({
      type: "Feature",
      id: h.id,
      // GeoJSON is longitude-first
      geometry: { type: "Point", coordinates: [h.longitude, h.latitude] },
      properties: {
        report_type: h.report_type,
        severity: h.severity,
        road_status: h.road_status,
        utility_lines_involved: h.utility_lines_involved,
        description: h.description,
        address: h.address,
        municipality: h.municipality,
        zipcode: h.zipcode,
        status: h.status,
        confirmations: h.upvotes,
        created_at: h.created_at,
        updated_at: h.updated_at,
        map_url: `https://www.google.com/maps/search/?api=1&query=${h.latitude},${h.longitude}`,
      },
    })),
  };
  return new Response(JSON.stringify(collection), {
    headers: { ...CORS, "Content-Type": "application/geo+json", "Cache-Control": "public, max-age=30" },
  });
});
