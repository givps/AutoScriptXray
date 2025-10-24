const WebSocket = require('ws');
const net = require('net');

const services = [
  {
    name: "Stunnel",
    wsPort: 1444,
    targetHost: "127.0.0.1",
    targetPort: 444
  },
  {
    name: "Dropbear",
    wsPort: 1445,
    targetHost: "127.0.0.1",
    targetPort: 109
  }
];

services.forEach(service => {
  const wss = new WebSocket.Server({ 
    port: service.wsPort,
    perMessageDeflate: false
  }, () => {
    console.log(`[${service.name}] WebSocket listening on port ${service.wsPort}`);
  });

  wss.on('connection', (ws, req) => {
    console.log(`[${service.name}] Client connected from ${req.socket.remoteAddress}`);
    const tcpSocket = net.connect({
      host: service.targetHost,
      port: service.targetPort,
      timeout: 10000
    }, () => console.log(`[${service.name}] Connected to ${service.targetHost}:${service.targetPort}`));

    ws.on('message', msg => tcpSocket.write(msg));
    tcpSocket.on('data', data => ws.readyState === WebSocket.OPEN && ws.send(data));

    ws.on('close', () => tcpSocket.end());
    tcpSocket.on('close', () => ws.close());
  });
});
