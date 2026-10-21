// OpenAI hazard triage for StormWatch NJ.
//
//   POST /analyze-image   multipart/form-data with an image in the "file" field
//
// Signed-in users only, so the OpenAI key cannot be spent by strangers. The key
// is read from the OPENAI_API_KEY function secret if set, otherwise from Supabase
// Vault (name "openai_api_key"). It lives only on the server, never in the app.
// The photo is passed to OpenAI for this one request and is not stored by
// StormWatch.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

const MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-mini";
const MAX_BYTES = 8 * 1024 * 1024;

const PROMPT = `You are StormWatch NJ's civic infrastructure triage assistant.
Inspect the storm incident photo.
1. Determine the primary hazard category.
2. Determine travel impassability and severity.
3. Crucial safety check: look carefully for utility or electrical wires that are down, or caught in fallen trees or water.
4. Write a concise 1-2 sentence factual description for a public works crew. Describe only what is visible; do not speculate.
If the photo does not show a storm hazard, answer OTHER with LOW severity and say so.`;

// Strict structured output: the model can only answer in this shape.
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    hazard_type: { type: "string", enum: ["CLOGGED_DRAIN", "STREET_FLOODING", "DOWNED_TREE", "DOWNED_WIRE", "OTHER"] },
    severity: { type: "string", enum: ["LOW", "MODERATE", "IMPASSABLE"] },
    utility_lines_involved: { type: "boolean" },
    road_status: { type: "string", enum: ["CLEAR_TO_PASS", "ONE_LANE_OPEN", "IMPASSABLE"] },
    suggested_description: { type: "string" },
  },
  required: ["hazard_type", "severity", "utility_lines_involved", "road_status", "suggested_description"],
};

// The web demo calls this from a browser, which first sends an OPTIONS preflight.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return reply({ detail: "Method not allowed." }, 405);

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: auth } = await admin.auth.getUser(token);
  if (!auth?.user) return reply({ detail: "Sign in to do that." }, 401);

  const key = Deno.env.get("OPENAI_API_KEY") ??
    (await admin.rpc("server_secret", { p_name: "openai_api_key" })).data;
  if (!key) return reply({ detail: "AI analysis isn't set up on the server yet." }, 503);

  let file: FormDataEntryValue | null;
  try {
    file = (await req.formData()).get("file");
  } catch {
    return reply({ detail: "Send the photo as multipart form data." }, 400);
  }
  if (!(file instanceof File) || !file.type.startsWith("image/")) return reply({ detail: "File must be an image." }, 400);
  if (file.size > MAX_BYTES) return reply({ detail: "Image is too large." }, 413);

  const image = `data:${file.type};base64,${encodeBase64(await file.arrayBuffer())}`;
  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.1,
        max_tokens: 300,
        messages: [{
          role: "user",
          content: [{ type: "text", text: PROMPT }, { type: "image_url", image_url: { url: image, detail: "low" } }],
        }],
        response_format: { type: "json_schema", json_schema: { name: "hazard_analysis", strict: true, schema: SCHEMA } },
      }),
      signal: AbortSignal.timeout(25_000),
    });
  } catch {
    return reply({ detail: "AI analysis timed out." }, 504);
  }
  if (!response.ok) {
    // Log the provider's answer for debugging; never echo it to the client.
    console.error("openai", response.status, (await response.text()).slice(0, 500));
    return reply({ detail: "AI analysis failed." }, 502);
  }
  try {
    return reply(JSON.parse((await response.json()).choices[0].message.content));
  } catch {
    return reply({ detail: "AI analysis returned an unreadable answer." }, 502);
  }
});
