import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { CHATBOT_INSTRUCTIONS, CHATBOT_MODEL, extractResponseText } from "./chatbot-config.mjs";

const root = resolve(process.argv[2] || "dist");
const port = Number(process.env.PORT || 3000);
const apiKey = process.env.OPENAI_API_KEY?.trim();
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
    res.writeHead(200, {
      "content-type": types[extname(file)] || "application/octet-stream",
      "x-content-type-options": "nosniff",
      "referrer-policy": "strict-origin-when-cross-origin",
    });
    res.end(data);
  } catch {
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
  return serveStatic(req, res, decodeURIComponent(url.pathname));
}).listen(port, "0.0.0.0", () => {
  console.log(`Mase the Creative running at http://localhost:${port}`);
  console.log(apiKey ? `Ask Mase is connected using ${CHATBOT_MODEL}` : "Ask Mase is running in safe demo mode");
});
