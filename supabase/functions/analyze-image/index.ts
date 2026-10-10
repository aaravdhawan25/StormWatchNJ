// Gemini hazard triage for StormWatch NJ.
//
//   POST /analyze-image   multipart/form-data with an image in the "file" field
//
// Signed-in users only, so the Gemini key cannot be spent by strangers. Needs the
// GEMINI_API_KEY secret; without it this returns 503 and the app falls back to
// its on-device analysis. The photo is passed to Gemini and not stored.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
const MAX_BYTES = 8 * 1024 * 1024;

const PROMPT = `You are StormWatch NJ's automated civic infrastructure triage assistant.
Inspect the uploaded storm incident photo.
1. Determine the primary hazard category.
2. Determine travel impassability and severity.
3. Crucial Safety Check: Look carefully for utility or electrical wires caught in fallen trees or water.
4. Output a clean, objective description. Describe only what is visible; do not speculate.`;

const SCHEMA = {
  type: "OBJECT",
  properties: {
    hazard_type: { type: "STRING", enum: ["CLOGGED_DRAIN", "STREET_FLOODING", "DOWNED_TREE", "DOWNED_WIRE", "OTHER"] },
    severity: { type: "STRING", enum: ["LOW", "MODERATE", "IMPASSABLE"] },
    utility_lines_involved: { type: "BOOLEAN", description: "True if electrical or utility lines appear snapped, tangled, or touching water/trees." },
    road_status: { type: "STRING", enum: ["CLEAR_TO_PASS", "ONE_LANE_OPEN", "IMPASSABLE"] },
    suggested_description: { type: "STRING", description: "Concise 1-2 sentence factual report for emergency DPW crew dispatch." },
  },
  required: ["hazard_type", "severity", "utility_lines_involved", "road_status", "suggested_description"],
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ detail: "Method not allowed." }, 405);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: auth } = await admin.auth.getUser(token);
  if (!auth?.user) return reply({ detail: "Sign in to do that." }, 401);

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return reply({ detail: "Gemini is not configured on this server." }, 503);

  let file: FormDataEntryValue | null;
  try {
    file = (await req.formData()).get("file");
  } catch {
    return reply({ detail: "Send the photo as multipart form data." }, 400);
  }
  if (!(file instanceof File) || !file.type.startsWith("image/")) return reply({ detail: "File must be an image." }, 400);
  if (file.size > MAX_BYTES) return reply({ detail: "Image is too large." }, 413);

  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify({
      contents: [{ parts: [{ inline_data: { mime_type: file.type, data: encodeBase64(await file.arrayBuffer()) } }, { text: PROMPT }] }],
      generationConfig: { responseMimeType: "application/json", responseSchema: SCHEMA, temperature: 0.1 },
    }),
    signal: AbortSignal.timeout(25_000),
  });
  if (!response.ok) {
    console.error("gemini", response.status, await response.text());
    return reply({ detail: "AI vision processing failed." }, 502);
  }
  try {
    const text = (await response.json()).candidates[0].content.parts[0].text;
    return reply(JSON.parse(text));
  } catch {
    return reply({ detail: "AI vision returned an unreadable answer." }, 502);
  }
});
