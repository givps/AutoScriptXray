const http = require('http');
const net = require('net');

const WS_PORT = 1445;      // none TLS
const WSS_PORT = 1444;     // TLS via stunnel
const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = 109;

function createServer(listenPort, label) {
  const server = http.createServer();

  server.on('connect', (req, clientSocket, head) => {
    const remote = net.connect(TARGET_PORT, TARGET_HOST, () => {
      clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      remote.write(head);
      remote.pipe(clientSocket);
      clientSocket.pipe(remote);
    });
  });

  server.on('request', (req, res) => {
    const remote = net.connect(TARGET_PORT, TARGET_HOST, () => {
      req.socket.pipe(remote);
      remote.pipe(req.socket);
    });
  });

  server.on('upgrade', (req, socket) => {
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n' +
      'Connection: Upgrade\r\n' +
      'Upgrade: websocket\r\n' +
      '\r\n'
    );
    const remote = net.connect(TARGET_PORT, TARGET_HOST);
    socket.pipe(remote);
    remote.pipe(socket);
  });

  server.listen(listenPort, '0.0.0.0', () => {
    console.log(`[${label}] Listening on port ${listenPort}`);
  });
}

createServer(WS_PORT, 'WS');
createServer(WSS_PORT, 'WSS');
