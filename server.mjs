import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { CHATBOT_INSTRUCTIONS, CHATBOT_MODEL, extractResponseText } from "./chatbot-config.mjs";

const root = resolve(process.argv[2] || "dist");
const port = Number(process.env.PORT || 3000);
const apiKey = process.env.OPENAI_API_KEY?.trim();
const supabaseUrl = process.env.SUPABASE_URL?.trim();
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
const siteUrl = (process.env.SITE_URL?.trim() || "https://masethecreative.co.uk").replace(/\/$/, "");
const supabaseAdmin = supabaseUrl && supabaseServiceKey
  ? createClient(supabaseUrl, supabaseServiceKey, { auth: { autoRefreshToken: false, persistSession: false } })
  : null;
const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".xml": "application/xml",
  ".txt": "text/plain; charset=utf-8",
};
const rateLimits = new Map();
const portalRateLimits = new Map();

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  res.end(JSON.stringify(body));
}

function clientIp(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || req.socket.remoteAddress || "unknown";
}

function withinRateLimit(req) {
  const ip = clientIp(req);
  const now = Date.now();
  const windowMs = 10 * 60 * 1000;
  const entry = rateLimits.get(ip);
  if (!entry || now - entry.startedAt > windowMs) {
    rateLimits.set(ip, { startedAt: now, count: 1 });
    return true;
  }
  entry.count += 1;
  return entry.count <= 24;
}

async function readJson(req) {
  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 16_000) throw new Error("payload_too_large");
  }
  return JSON.parse(body || "{}");
}

function withinPortalRateLimit(req) {
  const ip = clientIp(req);
  const now = Date.now();
  const windowMs = 10 * 60 * 1000;
  const entry = portalRateLimits.get(ip);
  if (!entry || now - entry.startedAt > windowMs) {
    portalRateLimits.set(ip, { startedAt: now, count: 1 });
    return true;
  }
  entry.count += 1;
  return entry.count <= 30;
}

async function requirePortalAdmin(req, res) {
  if (!supabaseAdmin) {
    json(res, 503, { error: "The workspace administration service is not configured." });
    return null;
  }
  const match = /^Bearer ([A-Za-z0-9._~-]+)$/.exec(req.headers.authorization || "");
  if (!match) {
    json(res, 401, { error: "A valid workspace session is required." });
    return null;
  }
  const { data, error } = await supabaseAdmin.auth.getUser(match[1]);
  if (error || !data.user) {
    json(res, 401, { error: "Your workspace session has expired." });
    return null;
  }
  const { data: admin } = await supabaseAdmin.from("app_admins").select("user_id").eq("user_id", data.user.id).maybeSingle();
  if (!admin) {
    json(res, 403, { error: "Mase administrator access is required." });
    return null;
  }
  return data.user;
}

function validEmail(value) {
  return typeof value === "string" && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

async function handleCreateOrganisation(req, res) {
  if (!withinPortalRateLimit(req)) return json(res, 429, { error: "Too many requests. Please wait and try again." });
  if (!await requirePortalAdmin(req, res)) return;
  let payload;
  try { payload = await readJson(req); } catch { return json(res, 400, { error: "Invalid request." }); }
  const name = typeof payload.name === "string" ? payload.name.trim() : "";
  const slug = typeof payload.slug === "string" ? payload.slug.trim().toLowerCase() : "";
  const industry = typeof payload.industry === "string" ? payload.industry.trim() : "";
  if (!name || name.length > 120 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || slug.length > 80 || industry.length > 120) {
    return json(res, 400, { error: "Enter a valid client name and lowercase workspace slug." });
  }
  const { data, error } = await supabaseAdmin.from("organisations").insert({ name, slug, industry: industry || null }).select("id,name,slug,industry,active").single();
  if (error) return json(res, error.code === "23505" ? 409 : 400, { error: error.code === "23505" ? "That workspace slug is already in use." : "The client workspace could not be created." });
  const [{ error: profileError }, { error: briefError }] = await Promise.all([
    supabaseAdmin.from("client_profiles").insert({ organisation_id: data.id }),
    supabaseAdmin.from("client_briefs").insert({ organisation_id: data.id }),
  ]);
  if (profileError || briefError) {
    await supabaseAdmin.from("organisations").delete().eq("id", data.id);
    return json(res, 500, { error: "The client workspace could not be initialised." });
  }
  return json(res, 201, { organisation: data });
}

async function handleInvite(req, res) {
  if (!withinPortalRateLimit(req)) return json(res, 429, { error: "Too many requests. Please wait and try again." });
  if (!await requirePortalAdmin(req, res)) return;
  let payload;
  try { payload = await readJson(req); } catch { return json(res, 400, { error: "Invalid request." }); }
  const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
  const fullName = typeof payload.fullName === "string" ? payload.fullName.trim() : "";
  const organisationId = typeof payload.organisationId === "string" ? payload.organisationId : "";
  const role = typeof payload.role === "string" ? payload.role : "";
  if (!validEmail(email) || !fullName || fullName.length > 120 || !/^[0-9a-f-]{36}$/i.test(organisationId) || !["admin", "client", "collaborator"].includes(role)) {
    return json(res, 400, { error: "Enter a valid name, email address, organisation and role." });
  }
  const { data: organisation } = await supabaseAdmin.from("organisations").select("id").eq("id", organisationId).is("archived_at", null).maybeSingle();
  if (!organisation) return json(res, 404, { error: "That client workspace could not be found." });
  const { data, error } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, { data: { full_name: fullName }, redirectTo: `${siteUrl}/portal/` });
  if (error || !data.user) {
    const exists = /already|registered|exists/i.test(error?.message || "");
    return json(res, exists ? 409 : 400, { error: exists ? "That email already has an account. Add it through Supabase or use a different address." : "The invitation could not be sent." });
  }
  const { error: profileError } = await supabaseAdmin.from("profiles").upsert({ id: data.user.id, full_name: fullName });
  const { error: memberError } = await supabaseAdmin.from("organisation_members").insert({ organisation_id: organisationId, user_id: data.user.id, role });
  if (profileError || memberError) {
    await supabaseAdmin.auth.admin.deleteUser(data.user.id);
    return json(res, 500, { error: "The invitation was cancelled because workspace access could not be linked." });
  }
  return json(res, 201, { userId: data.user.id });
}

async function handleChat(req, res) {
  if (!withinRateLimit(req)) return json(res, 429, { error: "Too many messages. Please wait a few minutes and try again." });

  let payload;
  try {
    payload = await readJson(req);
  } catch (error) {
    return json(res, error.message === "payload_too_large" ? 413 : 400, { error: "Invalid request." });
  }

  const message = typeof payload.message === "string" ? payload.message.trim() : "";
  const previousResponseId = typeof payload.previousResponseId === "string" ? payload.previousResponseId : "";
  if (!message || message.length > 1_200) return json(res, 400, { error: "Please enter a message between 1 and 1,200 characters." });
  if (previousResponseId && (!previousResponseId.startsWith("resp_") || previousResponseId.length > 200)) {
    return json(res, 400, { error: "Invalid conversation reference." });
  }
  if (!apiKey) return json(res, 503, { error: "Demo mode is active until an API key is configured.", demo: true });

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 22_000);
  try {
    const request = {
      model: CHATBOT_MODEL,
      instructions: CHATBOT_INSTRUCTIONS,
      input: message,
      reasoning: { effort: "low" },
      text: { verbosity: "low" },
      max_output_tokens: 500,
    };
    if (previousResponseId) request.previous_response_id = previousResponseId;

    const openaiResponse = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(request),
      signal: controller.signal,
    });
    const response = await openaiResponse.json();
    if (!openaiResponse.ok) {
      console.error(`OpenAI request failed with status ${openaiResponse.status}`);
      return json(res, 502, { error: "The assistant is temporarily unavailable." });
    }
    const text = extractResponseText(response);
    if (!text) return json(res, 502, { error: "The assistant returned an empty response." });
    return json(res, 200, { message: text, responseId: response.id });
  } catch (error) {
    const message = error.name === "AbortError" ? "The assistant took too long to reply." : "The assistant is temporarily unavailable.";
    return json(res, 502, { error: message });
  } finally {
    clearTimeout(timeout);
  }
}

async function serveStatic(req, res, pathname) {
  try {
    let file = resolve(root, `.${pathname}`);
    if (!file.startsWith(root)) throw new Error("invalid_path");
    if ((await stat(file).catch(() => null))?.isDirectory()) file = join(file, "index.html");
    const data = await readFile(file);
    const headers = {
      "content-type": types[extname(file)] || "application/octet-stream",
      "x-content-type-options": "nosniff",
      "referrer-policy": "strict-origin-when-cross-origin",
      "permissions-policy": "camera=(), microphone=(), geolocation=()",
    };
    if (pathname.startsWith("/portal")) {
      headers["cache-control"] = extname(file) === ".html" ? "no-store" : "public, max-age=3600";
      headers["content-security-policy"] = "default-src 'self'; connect-src 'self' https://*.supabase.co wss://*.supabase.co; img-src 'self' data: blob:; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'";
    }
    res.writeHead(200, headers);
    res.end(data);
  } catch {
    if (pathname.startsWith("/portal/") && !extname(pathname)) {
      const portal = await readFile(join(root, "portal", "index.html")).catch(() => null);
      if (portal) {
        res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "content-security-policy": "default-src 'self'; connect-src 'self' https://*.supabase.co wss://*.supabase.co; img-src 'self' data: blob:; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'" });
        return res.end(portal);
      }
    }
    const fallback = await readFile(join(root, "404.html")).catch(() => Buffer.from("Not found"));
    res.writeHead(404, { "content-type": "text/html; charset=utf-8" });
    res.end(fallback);
  }
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  if (url.pathname === "/api/chat") {
    if (req.method !== "POST") {
      res.setHeader("allow", "POST");
      return json(res, 405, { error: "Method not allowed." });
    }
    return handleChat(req, res);
  }
  if (url.pathname === "/api/portal/admin/organisations" || url.pathname === "/api/portal/admin/invite") {
    if (req.method !== "POST") {
      res.setHeader("allow", "POST");
      return json(res, 405, { error: "Method not allowed." });
    }
    return url.pathname.endsWith("/invite") ? handleInvite(req, res) : handleCreateOrganisation(req, res);
  }
  return serveStatic(req, res, decodeURIComponent(url.pathname));
}).listen(port, "0.0.0.0", () => {
  console.log(`Mase the Creative running at http://localhost:${port}`);
  console.log(apiKey ? `Ask Mase is connected using ${CHATBOT_MODEL}` : "Ask Mase is running in safe demo mode");
});
