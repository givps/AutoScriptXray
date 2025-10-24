#!/bin/bash
# =========================================
# COMPLETE SSH & WEBSOCKET INSTALLATION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

clear
echo -e "${red}=========================================${nc}"
echo -e "${red}    COMPLETE SSH & WEBSOCKET SETUP     ${nc}"
echo -e "${red}=========================================${nc}"

# =========================================
# VARIABLES
# =========================================
SERVER_IP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
LOG_FILE="/var/log/ssh-ws-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${yellow}Starting installation...${nc}"
echo -e "Server IP: $SERVER_IP"
echo -e "Log file: $LOG_FILE"

# =========================================
# SYSTEM PREPARATION
# =========================================
echo -e "\n${blue}[1/8] System Preparation${nc}"

# Update system
apt update -y
apt upgrade -y

# Install dependencies
apt install -y curl wget net-tools build-essential iptables-persistent

# Disable ufw jika ada
systemctl stop ufw 2>/dev/null
systemctl disable ufw 2>/dev/null

# =========================================
# INSTALL NODE.JS & DEPENDENCIES
# =========================================
echo -e "\n${blue}[2/8] Installing Node.js${nc}"
apt remove -y nodejs npm || true
# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Verify installation
echo -e "Node.js: $(node -v)"
echo -e "NPM: $(npm -v)"

# =========================================
# INSTALL HAPROXY
# =========================================
echo -e "\n${blue}[3/8] Installing HAProxy${nc}"

apt install -y haproxy

# Auto-detect Xray SSL and convert
XRAY_DIR="/usr/local/etc/xray"

# Cari file SSL Xray
CERT=$(find $XRAY_DIR -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" | head -1)
KEY=$(find $XRAY_DIR -name "*.key" -o -name "private.key" | head -1)

if [ -f "$CERT" ] && [ -f "$KEY" ]; then
    mkdir -p /etc/haproxy/ssl
    cat "$CERT" "$KEY" > /etc/haproxy/ssl/cert.pem
    chmod 600 /etc/haproxy/ssl/cert.pem
    chown haproxy:haproxy /etc/haproxy/ssl/cert.pem
    echo "✅ SSL converted from Xray"
else
    echo "❌ Xray SSL not found"
fi

# =========================================
# CONFIGURE HAPROXY
# username=admin password=generated random
Pass=`</dev/urandom tr -dc a-zA-Z0-9 | head -c10`
# =========================================
echo -e "\n${blue}[4/8] Configuring HAProxy${nc}"

cat > /etc/haproxy/haproxy.cfg << EOF
global
    daemon
    maxconn 4096
    tune.ssl.default-dh-param 2048
    log /dev/log local0
    log /dev/log local1 notice

defaults
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    log global
    option tcplog
    option dontlognull
    retries 3

# Frontend untuk WebSocket SSL pada port 1443
frontend ws_ssl_frontend
    bind *:1443 ssl crt /etc/haproxy/ssl/cert.pem
    mode tcp
    option tcplog
    
    # Routing ke backend SSH WebSocket
    use_backend ssh_ws_backend

# Frontend untuk WebSocket non-SSL pada port 1444
frontend ws_non_ssl_frontend
    bind *:1444
    mode tcp
    option tcplog
    
    use_backend ssh_ws_backend

# Backend untuk SSH WebSocket (OpenSSH)
backend ssh_ws_backend
    mode tcp
    balance first
    option tcp-check
    server ssh_ws1 127.0.0.1:2444 check inter 2000 rise 2 fall 3

# Stats page untuk monitoring
listen stats
    bind *:1936
    mode http
    stats enable
    stats hide-version
    stats uri /
    stats auth admin:${Pass}
EOF

systemctl enable haproxy
systemctl start haproxy

# =========================================
# CREATE WEBSOCKET PROXY
# =========================================
echo -e "\n${blue}[5/8] Creating WebSocket Proxy${nc}"

cat > /usr/local/bin/ws-proxy.js << 'EOF'
const WebSocket = require('ws');
const net = require('net');

// Service WebSocket - hanya satu service untuk SSH
const services = [
   {
    name: "SSH WebSocket",
    wsPort: 2444,
    targetHost: "127.0.0.1",
    targetPort: 22
   }
];

services.forEach(service => {
  const wss = new WebSocket.Server({ 
    port: service.wsPort,
    host: '0.0.0.0',
    perMessageDeflate: false
  }, () => {
    console.log(`[${service.name}] WebSocket listening on port ${service.wsPort}`);
  });

  wss.on('connection', (ws, req) => {
    console.log(`[${service.name}] New client from ${req.socket.remoteAddress}`);
    
    const tcpSocket = net.connect({
      host: service.targetHost,
      port: service.targetPort
    }, () => {
      console.log(`[${service.name}] Connected to OpenSSH ${service.targetHost}:${service.targetPort}`);
    });

    // Cleanup function
    const cleanup = () => {
      ws.removeAllListeners('message');
      ws.removeAllListeners('close');
      ws.removeAllListeners('error');
      tcpSocket.removeAllListeners('data');
      tcpSocket.removeAllListeners('close');
      tcpSocket.removeAllListeners('error');
    };

    // WebSocket -> TCP
    ws.on('message', (msg) => {
      if (tcpSocket.writable) {
        tcpSocket.write(msg);
      }
    });

    // TCP -> WebSocket  
    tcpSocket.on('data', (data) => {
      if (ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(data);
        } catch (err) {
          console.log(`[${service.name}] Failed to send data to WebSocket:`, err.message);
        }
      }
    });

    ws.on('close', () => {
      console.log(`[${service.name}] Client disconnected`);
      cleanup();
      tcpSocket.end();
    });

    tcpSocket.on('close', () => {
      console.log(`[${service.name}] OpenSSH connection closed`);
      cleanup();
      if (ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    });

    tcpSocket.on('error', (err) => {
      console.log(`[${service.name}] OpenSSH Error:`, err.message);
      cleanup();
      ws.close();
    });

    ws.on('error', (err) => {
      console.log(`[${service.name}] WS Error:`, err.message);
      cleanup();
      tcpSocket.end();
    });
  });

  wss.on('error', (err) => {
    console.log(`[${service.name}] WS Server Error:`, err.message);
  });
});

console.log('=========================================');
console.log('WebSocket Proxy Started');
console.log('Single endpoint for SSH WebSocket');
console.log('=========================================');
EOF

# Install dependencies
cd /usr/local/bin
npm install ws

# Create systemd service untuk WebSocket proxy
cat > /etc/systemd/system/ws-proxy.service << 'EOF'
[Unit]
Description=WebSocket Proxy for SSH
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/node /usr/local/bin/ws-proxy.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chmod +x /usr/local/bin/ws-proxy.js
systemctl daemon-reload
systemctl enable ws-proxy
systemctl start ws-proxy

# =========================================
# CONFIGURE SSH DIRECT PORTS
# =========================================
echo -e "\n${blue}[6/8] Configuring SSH Direct Ports${nc}"

# Backup SSH config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Update SSH config untuk listen multiple ports
cat >> /etc/ssh/sshd_config << 'EOF'
# =========================================
# SSHD Configuration - HAProxy WebSocket
# Optimized for SSH & WebSocket Proxy
# =========================================

# Basic Settings
Port 22
Port 2222
Port 1445
Port 1446
Protocol 2

# Security Settings
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Connection Settings
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:100

# Authentication Settings
PubkeyAuthentication yes
IgnoreRhosts yes
HostbasedAuthentication no
RhostsRSAAuthentication no

# Encryption Settings
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256

# Logging Settings
SyslogFacility AUTH
LogLevel INFO

# Performance Settings
Compression delayed
UseDNS no
GSSAPIAuthentication no

# Match blocks for specific configurations
# Allow HAProxy local connections
Match Address 127.0.0.1
    PasswordAuthentication yes
    AllowTcpForwarding yes
    PermitTTY yes

# End of configuration
EOF

systemctl restart ssh

# =========================================
# CONFIGURE IPTABLES
# =========================================
echo -e "\n${blue}[7/8] Configuring iptables${nc}"

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH on default port
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT

# Allow public ports
iptables -A INPUT -p tcp --dport 1443 -j ACCEPT  # HAProxy SSL WS
iptables -A INPUT -p tcp --dport 1444 -j ACCEPT  # HAProxy non-SSL WS
iptables -A INPUT -p tcp --dport 1445 -j ACCEPT  # SSH Direct SSL
iptables -A INPUT -p tcp --dport 1446 -j ACCEPT  # SSH Direct non-SSL
iptables -A INPUT -p tcp --dport 1936 -j ACCEPT  # HAProxy Stats
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT

# Allow ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# Save iptables rules
netfilter-persistent save
netfilter-persistent reload

# =========================================
# FINAL SETUP & VERIFICATION
# =========================================
echo -e "\n${blue}[8/8] Final Verification${nc}"

# Restart services
systemctl restart ssh haproxy ws-proxy

sleep 3

# Verification
echo -e "${yellow}🔧 Service Status:${nc}"
echo -e "OpenSSH: $(systemctl is-active ssh)"
echo -e "HAProxy: $(systemctl is-active haproxy)"
echo -e "WS-Proxy: $(systemctl is-active ws-proxy)"

echo -e "\n${yellow}🌐 Listening Ports:${nc}"
netstat -tulpn | grep -E ':(22|1443|1444|1445|1446|1936|2444)'

echo -e "\n${green}✅ INSTALLATION COMPLETED!${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${blue}           CONFIGURATION SUMMARY        ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}🌐 WebSocket Connections:${nc}"
echo -e "  SSL (Port 1443)    : ${yellow}wss://$SERVER_IP:1443/${nc}"
echo -e "  Non-SSL (Port 1444): ${yellow}ws://$SERVER_IP:1444/${nc}"

echo -e "\n${green}🔌 Direct SSH:${nc}"
echo -e "  SSL (Port 1445)    : ${yellow}ssh -p 1445 user@$SERVER_IP${nc}"
echo -e "  Non-SSL (Port 1446): ${yellow}ssh -p 1446 user@$SERVER_IP${nc}"

echo -e "\n${green}📊 Monitoring:${nc}"
echo -e "  HAProxy Stats    : ${yellow}http://$SERVER_IP:1936/${nc}"
echo -e "  Username         : ${blue}admin${nc}"
echo -e "  Password         : ${red}${Pass}${nc}"
echo -e "  Installation Log : ${yellow}$LOG_FILE${nc}"

echo -e "\n${green}🔧 Management Commands:${nc}"
echo -e "  Restart all      : ${yellow}systemctl restart ssh haproxy ws-proxy${nc}"
echo -e "  Check status     : ${yellow}systemctl status haproxy ws-proxy${nc}"
echo -e "  View WS logs     : ${yellow}journalctl -u ws-proxy -f${nc}"

echo -e "\n${yellow}⚠️  Note: All traffic goes to OpenSSH on port 22 internally${nc}"
echo -e "${red}=========================================${nc}"

# Test connections
echo -e "\n${yellow}Testing connections...${nc}"
timeout 2 bash -c "echo > /dev/tcp/localhost/1443" && echo -e "✅ Port 1443 (HAProxy SSL) listening" || echo -e "❌ Port 1443 not responding"
timeout 2 bash -c "echo > /dev/tcp/localhost/1444" && echo -e "✅ Port 1444 (HAProxy non-SSL) listening" || echo -e "❌ Port 1444 not responding"
timeout 2 bash -c "echo > /dev/tcp/localhost/1445" && echo -e "✅ Port 1445 (SSH Direct SSL) listening" || echo -e "❌ Port 1445 not responding"
timeout 2 bash -c "echo > /dev/tcp/localhost/1446" && echo -e "✅ Port 1446 (SSH Direct non-SSL) listening" || echo -e "❌ Port 1446 not responding"

echo -e "\n${green}🎯 Setup completed successfully!${nc}"
echo -e "${yellow}You can now test the connections using the information above.${nc}"

