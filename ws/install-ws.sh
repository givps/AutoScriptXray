#!/bin/bash
# ==========================================
# INSTALL WEBSOCKET PROXY.JS
# ==========================================
set -euo pipefail
LOG_FILE="/var/log/ws-proxy-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "Starting WebSocket Proxy.js installation..."
echo "========================================="

# -------------------------------
# Set non-interactive mode
# -------------------------------
export DEBIAN_FRONTEND=noninteractive

# -------------------------------
# Update & Install dependencies
# -------------------------------
echo "[STEP 1] Updating system and installing packages..."
apt update -y || true
apt upgrade -y || true
apt install -y wget curl lsof net-tools ufw build-essential || true
# -------------------------------
# Install Node.js
# -------------------------------
echo "[STEP 2] Checking Node.js version..."
NODE_VERSION=$(node -v 2>/dev/null || echo "v0")
NODE_MAJOR=${NODE_VERSION#v}
NODE_MAJOR=${NODE_MAJOR%%.*}

if [[ $NODE_MAJOR -lt 16 ]]; then
    echo "Node.js version too old ($NODE_VERSION). Installing Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - || true
    apt install -y nodejs || true
else
    echo "Node.js version is sufficient ($NODE_VERSION)"
fi

# -------------------------------
# Download proxy.js
# -------------------------------
echo "[STEP 3] Downloading proxy.js..."
wget -q -O /usr/local/bin/proxy.js https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/proxy.js
chmod +x /usr/local/bin/proxy.js
echo "[STEP 3] proxy.js installed at /usr/local/bin/proxy.js"

# -------------------------------
# Download systemd service
# -------------------------------
echo "[STEP 4] Setting up ws-proxy systemd service..."
wget -q -O /etc/systemd/system/ws-proxy.service https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/ws-proxy.service
chmod 644 /etc/systemd/system/ws-proxy.service

cd /usr/local/bin
npm install ws

# Reload systemd to recognize new service
systemctl daemon-reload || true

# Enable and start ws-proxy service
systemctl enable ws-proxy || true
systemctl restart ws-proxy || true

# -------------------------------
# Verify service
# -------------------------------
if systemctl is-active --quiet ws-proxy; then
    echo "[STEP 5] ws-proxy service is active and running."
else
    echo "[WARNING] ws-proxy service failed to start. Check logs with: journalctl -u ws-proxy -f"
fi

# -------------------------------
# Final message
# -------------------------------
echo "========================================="
echo "WebSocket Proxy.js installation complete!"
echo "You can check the service status: systemctl status ws-proxy"
echo "========================================="
