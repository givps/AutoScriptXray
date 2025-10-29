// Simple HTTP/WebSocket -> raw TCP proxy (accepts minimal Upgrade handshake)
const http = require('http');
const net = require('net');

const WS_PORT = Number(process.env.WS_PORT || 1445);
const WSS_PORT = Number(process.env.WSS_PORT || 1444);
const TARGET_HOST = process.env.TARGET_HOST || '127.0.0.1';
const TARGET_PORT = Number(process.env.TARGET_PORT || 109);
const BIND_HOST = process.env.BIND_HOST || '0.0.0.0';

function createServer(listenPort, label) {
  const server = http.createServer();

  server.on('connect', (req, clientSocket, head) => {
    console.log(`[${label}] CONNECT from ${req.socket.remoteAddress}:${req.socket.remotePort} -> ${req.url}`);
    const remote = net.connect(TARGET_PORT, TARGET_HOST, () => {
      clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      if (head && head.length) remote.write(head);
      clientSocket.pipe(remote);
      remote.pipe(clientSocket);
    });
    remote.on('error', (e) => { console.error(`[${label}] remote error:`, e.message); try { clientSocket.destroy(); } catch(_) {} });
  });

  server.on('request', (req, res) => {
    console.log(`[${label}] HTTP request from ${req.socket.remoteAddress}:${req.socket.remotePort} ${req.method} ${req.url}`);
    const clientSocket = req.socket;
    const remote = net.connect(TARGET_PORT, TARGET_HOST, () => {
      clientSocket.pipe(remote);
      remote.pipe(clientSocket);
    });
    remote.on('error', (e) => { console.error(`[${label}] remote error:`, e.message); try { clientSocket.end(); } catch(_) {} });
    remote.on('close', () => { try { clientSocket.end(); } catch(_) {} });
  });

  server.on('upgrade', (req, socket /* head */) => {
    console.log(`[${label}] Upgrade request from ${req.socket.remoteAddress}:${req.socket.remotePort} url=${req.url}`);
    try {
      socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
    } catch (e) { console.error(`[${label}] Failed to write 101:`, e.message); socket.destroy(); return; }

    const remote = net.connect(TARGET_PORT, TARGET_HOST, () => {
      socket.pipe(remote);
      remote.pipe(socket);
    });
    remote.on('error', (e) => { console.error(`[${label}] remote error:`, e.message); try { socket.destroy(); } catch(_) {} });
    socket.on('error', () => { try { remote.destroy(); } catch(_) {} });
  });

  server.listen(listenPort, BIND_HOST, () => {
    console.log(`[${label}] Listening on ${BIND_HOST}:${listenPort} -> ${TARGET_HOST}:${TARGET_PORT}`);
  });

  server.on('error', (err) => {
    console.error(`[${label}] server error:`, err.message);
  });

  return server;
}

createServer(WS_PORT, 'WS');
createServer(WSS_PORT, 'WSS');
