// WebSocket -> newline-JSON TCP bridge for the existing Lua server.
//
// Browser  --WSS-->  Caddy  --WS-->  this gateway  --TCP-->  game server
//
// This process deliberately does not understand game messages. It only relays
// complete newline-delimited lines in both directions.

const http = require("http");
const net = require("net");
const { WebSocketServer } = require("ws");

const GAME_HOST = process.env.GAME_HOST || "127.0.0.1";
const GAME_PORT = Number(process.env.GAME_PORT || 7777);
const GATEWAY_HOST = process.env.GATEWAY_HOST || "127.0.0.1";
const GATEWAY_PORT = Number(process.env.GATEWAY_PORT || 9001);
const MAX_CLIENTS = Number(process.env.MAX_CLIENTS || 2048);
const MAX_BUFFER = 256 * 1024;
const IDLE_MS = 45_000;

let active = 0;

const server = http.createServer((req, res) => {
  res.writeHead(404);
  res.end("websocket only");
});

const wss = new WebSocketServer({
  server,
  maxPayload: 128 * 1024,
  perMessageDeflate: false,
});

function safeSend(ws, text) {
  if (ws.readyState === ws.OPEN) ws.send(text);
}

wss.on("connection", (ws, req) => {
  if (active >= MAX_CLIENTS) {
    ws.close(1013, "gateway full");
    return;
  }
  active++;

  // Caddy sets this. The Lua server does not consume it yet; it is exposed
  // here so the next step (client-IP forwarding / PROXY protocol) is simple.
  const forwarded = String(req.headers["x-forwarded-for"] || "")
    .split(",")[0]
    .trim();

  const tcp = net.createConnection({ host: GAME_HOST, port: GAME_PORT });
  tcp.setNoDelay(true);

  let inbuf = "";
  let closed = false;
  let lastSeen = Date.now();

  const close = (why) => {
    if (closed) return;
    closed = true;
    active = Math.max(0, active - 1);
    try { tcp.destroy(); } catch {}
    try { ws.close(1000, why || "closed"); } catch {}
  };

  tcp.on("connect", () => {
    ws.send(JSON.stringify({ type: "gateway", status: "connected" }));
  });

  tcp.on("data", (chunk) => {
    lastSeen = Date.now();
    inbuf += chunk.toString("utf8");
    if (inbuf.length > MAX_BUFFER) {
      close("server buffer overflow");
      return;
    }
    let nl;
    while ((nl = inbuf.indexOf("\n")) >= 0) {
      const line = inbuf.slice(0, nl + 1);
      inbuf = inbuf.slice(nl + 1);
      safeSend(ws, line);
    }
  });

  ws.on("message", (data, isBinary) => {
    lastSeen = Date.now();
    if (isBinary) {
      close("binary frames unsupported");
      return;
    }
    const text = data.toString("utf8");
    if (!text.endsWith("\n")) tcp.write(text + "\n");
    else tcp.write(text);
  });

  ws.on("close", () => close("client closed"));
  ws.on("error", () => close("client error"));
  tcp.on("close", () => close("game server closed"));
  tcp.on("error", (err) => {
    console.error("tcp error", err.message);
    close("game server error");
  });

  // The Lua server always sends JSON lines. If the first bytes are not JSON,
  // this gateway is pointed at the wrong port.
  const timer = setInterval(() => {
    if (Date.now() - lastSeen > IDLE_MS) close("idle");
    if (ws.readyState === ws.OPEN) ws.ping();
  }, 15_000);
  timer.unref?.();
  ws.on("close", () => clearInterval(timer));
});

server.listen(GATEWAY_PORT, GATEWAY_HOST, () => {
  console.log(
    `gateway ws://${GATEWAY_HOST}:${GATEWAY_PORT} -> tcp://${GAME_HOST}:${GAME_PORT}`
  );
});
