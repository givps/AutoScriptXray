// proxy.js
// Usage: NODE_ENV=production WS_PORT=1444 SSH_TARGET_HOST=127.0.0.1 SSH_TARGET_PORT=109 node proxy.js

const WebSocket = require('ws');
const net = require('net');

const WS_PORT = Number(process.env.WS_PORT || 1444);
const SSH_TARGET_HOST = process.env.SSH_TARGET_HOST || '127.0.0.1';
const SSH_TARGET_PORT = Number(process.env.SSH_TARGET_PORT || 109);

// backpressure thresholds
const WS_PAUSE_THRESHOLD = 4 * 1024 * 1024; // 4MB of buffered ws data

const wss = new WebSocket.Server({
  port: WS_PORT,
  perMessageDeflate: false,
  maxPayload: 10 * 1024 * 1024 // 10MB
}, () => {
  console.log(`[proxy] WebSocket -> TCP proxy listening on ws:${WS_PORT} -> ${SSH_TARGET_HOST}:${SSH_TARGET_PORT}`);
});

wss.on('connection', (ws, req) => {
  const remote = req.socket.remoteAddress + ':' + req.socket.remotePort;
  console.log(`[proxy] New WS client ${remote}`);

  const tcp = net.connect({
    host: SSH_TARGET_HOST,
    port: SSH_TARGET_PORT,
    timeout: 15000
  });

  let closed = false;

  tcp.on('connect', () => {
    console.log(`[proxy] TCP connected to ${SSH_TARGET_HOST}:${SSH_TARGET_PORT} for client ${remote}`);
  });

  tcp.on('data', (chunk) => {
    // if ws is open, send binary
    if (ws.readyState === WebSocket.OPEN) {
      // backpressure: if ws bufferedAmount is big, pause tcp
      try {
        ws.send(chunk, { binary: true }, (err) => {
          if (err) {
            console.error(`[proxy] ws.send error for ${remote}:`, err.message || err);
            tcp.end();
          }
        });
      } catch (e) {
        console.error(`[proxy] exception sending to ws for ${remote}:`, e.message || e);
        tcp.end();
      }

      if (ws.bufferedAmount > WS_PAUSE_THRESHOLD) {
        // pause reading from TCP until websocket drains
        tcp.pause();
        // console.log(`[proxy] Paused TCP -> WS for ${remote}, bufferedAmount=${ws.bufferedAmount}`);
      }
    }
  });

  tcp.on('drain', () => {
    // resume if TCP was paused due to ws backpressure
    try { tcp.resume(); } catch (_) {}
  });

  tcp.on('error', (err) => {
    console.error(`[proxy] TCP error for ${remote}:`, err.message || err);
    if (!closed) {
      closed = true;
      ws.close();
      tcp.destroy();
    }
  });

  tcp.on('close', (hadErr) => {
    console.log(`[proxy] TCP closed for ${remote} (hadErr=${hadErr})`);
    if (!closed) {
      closed = true;
      try { ws.close(); } catch(_) {}
    }
  });

  tcp.on('timeout', () => {
    console.warn(`[proxy] TCP connect timeout for ${remote}`);
    tcp.end();
  });

  ws.on('message', (data, isBinary) => {
    // write directly to TCP socket; data can be Buffer or string
    if (!tcp.destroyed) {
      const ok = tcp.write(data);
      // if tcp write returned false, pause websocket receiving until 'drain'
      if (!ok) {
        // pause WS from emitting 'message' events using a simple backpressure flag
        // ws library does not expose pause(), but we can stop writing or buffer on TCP side.
        // Here we just log; in practice TCP write backpressure is rare for small ssh packets.
        // console.log(`[proxy] tcp write returned false for ${remote}`);
      }
    }
  });

  ws.on('close', (code, reason) => {
    console.log(`[proxy] WS closed for ${remote} code=${code} reason=${reason && reason.toString()}`);
    if (!closed) {
      closed = true;
      try { tcp.end(); } catch(_) {}
      tcp.destroy();
    }
  });

  ws.on('error', (err) => {
    console.error(`[proxy] WS error for ${remote}:`, err.message || err);
    if (!closed) {
      closed = true;
      try { tcp.end(); } catch(_) {}
      tcp.destroy();
    }
  });

  // If ws bufferedAmount drains, resume TCP if paused
  const drainCheck = setInterval(() => {
    if (tcp.destroyed) {
      clearInterval(drainCheck);
      return;
    }
    if (ws.readyState === WebSocket.OPEN && ws.bufferedAmount < WS_PAUSE_THRESHOLD / 2) {
      try { tcp.resume(); } catch (_) {}
    }
  }, 500);

});

wss.on('error', (err) => {
  console.error('[proxy] WebSocket Server error:', err.message || err);
});
