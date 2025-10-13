// proxy.js
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
    perMessageDeflate: false // Disable compression untuk performa
  }, () => {
    console.log(`[${service.name}] WebSocket listening on port ${service.wsPort}`);
  });

  wss.on('connection', (ws, req) => {
    console.log(`[${service.name}] New client connected from ${req.socket.remoteAddress}`);
    
    const tcpSocket = net.connect({
      host: service.targetHost,
      port: service.targetPort,
      timeout: 10000 // 10 detik timeout
    }, () => {
      console.log(`[${service.name}] Connected to target ${service.targetHost}:${service.targetPort}`);
    });

    // Fungsi cleanup
    const cleanup = () => {
      ws.removeAllListeners('message');
      ws.removeAllListeners('close');
      ws.removeAllListeners('error');
      tcpSocket.removeAllListeners('data');
      tcpSocket.removeAllListeners('close');
      tcpSocket.removeAllListeners('error');
    };

    // WebSocket -> TCP
    const wsMessageHandler = (msg) => {
      if (tcpSocket.writable) {
        tcpSocket.write(msg);
      }
    };

    // TCP -> WebSocket
    const tcpDataHandler = (data) => {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(data);
        } catch (err) {
          console.log(`[${service.name}] Failed to send data to WebSocket:`, err.message);
        }
      }
    };

    ws.on('message', wsMessageHandler);
    tcpSocket.on('data', tcpDataHandler);

    ws.on('close', (code, reason) => {
      console.log(`[${service.name}] Client disconnected: ${code} - ${reason}`);
      cleanup();
      tcpSocket.end();
    });

    tcpSocket.on('close', (hadError) => {
      console.log(`[${service.name}] Target connection closed ${hadError ? 'with error' : 'normally'}`);
      cleanup();
      if (ws.readyState === WebSocket.OPEN) {
        ws.close(1000, 'Target connection closed');
      }
    });

    tcpSocket.on('error', (err) => {
      console.log(`[${service.name}] TCP Error:`, err.message);
      cleanup();
      if (ws.readyState === WebSocket.OPEN) {
        ws.close(1011, 'Target connection error');
      }
    });

    ws.on('error', (err) => {
      console.log(`[${service.name}] WS Error:`, err.message);
      cleanup();
      tcpSocket.end();
    });

    // Timeout handling
    const timeout = setTimeout(() => {
      if (tcpSocket.connecting) {
        console.log(`[${service.name}] Connection timeout`);
        tcpSocket.destroy();
        ws.close(1011, 'Connection timeout');
      }
    }, 15000);

    tcpSocket.on('connect', () => {
      clearTimeout(timeout);
    });
  });

  wss.on('error', (err) => {
    console.log(`[${service.name}] WS Server Error:`, err.message);
  });

  wss.on('close', () => {
    console.log(`[${service.name}] WebSocket server closed`);
  });
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down servers...');
  process.exit(0);
});
