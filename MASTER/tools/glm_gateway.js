#!/usr/bin/env node
// Local loopback OpenAI-compatible gateway fronting the internal z.ai endpoint.
// Pair with glm_env.sh: MASTER_LLM_GATEWAY_URL=http://127.0.0.1:8787/v1 wires
// MASTER's hosted sender to it, and MASTER_MODEL=gateway:<id> forces the lane
// onto every chain. Secrets are read from GLM_GATEWAY_CONFIG (default
// /etc/.z-ai-config) at request time and never logged. GLM_GATEWAY_PORT
// (default 8787) moves the listener when the port is taken.
const http = require("http");
const fs = require("fs");

const PORT = Number(process.env.GLM_GATEWAY_PORT) || 8787;
const CONFIG = process.env.GLM_GATEWAY_CONFIG || "/etc/.z-ai-config";
const cfg = () => JSON.parse(fs.readFileSync(CONFIG, "utf8"));

function upstreamHeaders() {
  const c = cfg();
  const h = {
    "Content-Type": "application/json",
    Authorization: "Bearer " + c.apiKey,
    "X-Z-AI-From": "Z",
  };
  if (c.chatId) h["X-Chat-Id"] = c.chatId;
  if (c.userId) h["X-User-Id"] = c.userId;
  if (c.token) h["X-Token"] = c.token;
  return h;
}

const server = http.createServer(async (req, res) => {
  const c = cfg();
  const base = c.baseUrl.replace(/\/$/, "");
  const path = req.url.replace(/^\/v1/, ""); // tolerate either /models or /v1/models

  if (req.method === "GET" && path.startsWith("/models")) {
    // The listing MASTER's HostedEndpoints discovery consumes; ids become
    // "gateway:<id>" lanes. glm-5.3 first: the primary #1 id for this session.
    const body = JSON.stringify({
      object: "list",
      data: [
        { id: "glm-5.3", object: "model", owned_by: "zai" },
        { id: "glm-5.3-flash", object: "model", owned_by: "zai" },
      ],
    });
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(body);
  }

  if (req.method === "POST" && path.startsWith("/chat/completions")) {
    const chunks = [];
    for await (const ch of req) chunks.push(ch);
    let body;
    try {
      body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      return res.end(JSON.stringify({ error: { message: "bad JSON body" } }));
    }
    body.thinking = (body && body.thinking) || { type: "disabled" };
    // OpenAI multimodal shape (typed content arrays with image_url parts)
    // routes to the internal vision endpoint; plain text stays on chat.
    const hasImage = Array.isArray(body?.messages) && body.messages.some((m) =>
      Array.isArray(m?.content) && m.content.some((p) => p?.type === "image_url"));
    const target = hasImage ? "/chat/completions/vision" : "/chat/completions";
    const payload = JSON.stringify(body);

    try {
      const up = await fetch(base + target, {
        method: "POST",
        headers: upstreamHeaders(),
        body: payload,
      });
      res.writeHead(up.status, {
        "Content-Type": up.headers.get("content-type") || "application/json",
      });
      if (up.body) {
        // stream passthrough (SSE or plain)
        const reader = up.body.getReader();
        (async () => {
          try {
            for (;;) {
              const { done, value } = await reader.read();
              if (done) break;
              res.write(Buffer.from(value));
            }
          } catch (e) {
            res.write("\n\nevent: error\n");
          }
          res.end();
        })();
      } else {
        res.end();
      }
    } catch (e) {
      res.writeHead(502, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: { message: "upstream failed", type: e.message } }));
    }
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: { message: "not found: " + req.url } }));
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`glm gateway listening on http://127.0.0.1:${PORT}/v1`);
});
