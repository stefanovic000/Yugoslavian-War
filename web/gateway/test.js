// Integration smoke test for the WebSocket -> TCP bridge.
// Starts a dummy newline-JSON TCP server, starts the gateway, connects a
// WebSocket client and verifies both directions.

const net = require("net");
const { spawn } = require("child_process");
const WebSocket = require("ws");

const TCP_PORT = 7790;
const WS_PORT = 9002;

const tcpServer = net.createServer((socket) => {
  let buf = "";
  socket.on("data", (chunk) => {
    buf += chunk.toString("utf8");
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl);
      buf = buf.slice(nl + 1);
      const msg = JSON.parse(line);
      socket.write(JSON.stringify({ type: "echo", text: msg.text }) + "\n");
    }
  });
});

tcpServer.listen(TCP_PORT, "127.0.0.1", () => {
  const gw = spawn(process.execPath, ["server.js"], {
    env: {
      ...process.env,
      GAME_HOST: "127.0.0.1",
      GAME_PORT: String(TCP_PORT),
      GATEWAY_HOST: "127.0.0.1",
      GATEWAY_PORT: String(WS_PORT),
    },
    stdio: "ignore",
  });

  const timer = setTimeout(() => {
    console.error("TIMEOUT");
    gw.kill();
    tcpServer.close();
    process.exit(1);
  }, 5000);

  const connect = (attempt) => {
    const ws = new WebSocket(`ws://127.0.0.1:${WS_PORT}`);
    ws.on("open", () => {
      ws.send(JSON.stringify({ text: "hello" }) + "\n");
    });
    ws.on("message", (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.type === "echo" && msg.text === "hello") {
        clearTimeout(timer);
        console.log("GATEWAY OK");
        ws.close();
        gw.kill();
        tcpServer.close();
        process.exit(0);
      }
    });
    ws.on("error", () => {
      if (attempt < 20) setTimeout(() => connect(attempt + 1), 100);
    });
  };
  setTimeout(() => connect(1), 150);
});
