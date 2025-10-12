// proxy.js

const WebSocket = require('ws');
const net = require('net');

// service WebSocket
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
  const wss = new WebSocket.Server({ port: service.wsPort }, () => {
    console.log(`[${service.name}] WebSocket listening on port ${service.wsPort}`);
  });

  wss.on('connection', ws => {
    console.log(`[${service.name}] New client connected`);
    
    const tcpSocket = net.connect(service.targetPort, service.targetHost, () => {
      console.log(`[${service.name}] Connected to target ${service.targetHost}:${service.targetPort}`);
    });

    ws.on('message', msg => {
      tcpSocket.write(msg);
    });

    tcpSocket.on('data', data => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(data);
      }
    });

    ws.on('close', () => {
      tcpSocket.end();
      console.log(`[${service.name}] Client disconnected`);
    });

    tcpSocket.on('close', () => {
      ws.close();
      console.log(`[${service.name}] Target connection closed`);
    });

    tcpSocket.on('error', err => {
      console.log(`[${service.name}] TCP Error:`, err.message);
      ws.close();
    });

    ws.on('error', err => {
      console.log(`[${service.name}] WS Error:`, err.message);
      tcpSocket.end();
    });
  });

  wss.on('error', err => {
    console.log(`[${service.name}] WS Server Error:`, err.message);
  });
});
