// proxy.js
const http = require("http");
const WebSocket = require("ws");
const net = require("net");

// === WSS NONE TLS STUNNEL ===
const wsServer = http.createServer();
const wss = new WebSocket.Server({ server: wsServer });

wss.on("connection", (ws, req) => {
  console.log("[WS] Client:", req.socket.remoteAddress);
  const ssh = net.connect({ host: "127.0.0.1", port: 109 });

  ws.on("message", msg => ssh.write(msg));
  ssh.on("data", data => ws.readyState === WebSocket.OPEN && ws.send(data));

  ws.on("close", () => ssh.end());
  ssh.on("close", () => ws.close());
});

wsServer.listen(1445, () => {
  console.log("[WS] Listening on port 1445 (no TLS)");
});

// === WSS VIA STUNNEL ===
const tlsServer = http.createServer();
const wssTLS = new WebSocket.Server({ server: tlsServer });

wssTLS.on("connection", (ws, req) => {
  console.log("[WSS] Client:", req.socket.remoteAddress);
  const ssh = net.connect({ host: "127.0.0.1", port: 109 });

  ws.on("message", msg => ssh.write(msg));
  ssh.on("data", data => ws.readyState === WebSocket.OPEN && ws.send(data));

  ws.on("close", () => ssh.end());
  ssh.on("close", () => ws.close());
});

tlsServer.listen(1443, "127.0.0.1", () => {
  console.log("[WSS] Listening on 127.0.0.1:1443 (for stunnel)");
});
