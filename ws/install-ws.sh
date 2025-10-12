#!/bin/bash
# ==========================================
# INSTALL WEBSOCKET PROXY.JS
# ==========================================

LOG_FILE="/var/log/ws-proxy-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "Starting WebSocket Proxy.js installation..."
echo "========================================="

# -------------------------------
# Update & Install dependencies
# -------------------------------
echo "[STEP 1] Updating system and installing packages..."
apt update -y && apt upgrade -y
apt install -y wget curl lsof net-tools ufw build-essential

# -------------------------------
# Install Node.js
# -------------------------------
echo "[STEP 2] Checking Node.js version..."
NODE_VERSION=$(node -v 2>/dev/null || echo "v0")
NODE_MAJOR=${NODE_VERSION#v}
NODE_MAJOR=${NODE_MAJOR%%.*}

if [[ $NODE_MAJOR -lt 16 ]]; then
    echo "Node.js version too old ($NODE_VERSION). Installing Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
else
    echo "Node.js version is sufficient ($NODE_VERSION)"
fi

# -------------------------------
# Download proxy.js
# -------------------------------
echo "[STEP 3] Downloading proxy.js..."
wget -O /usr/local/bin/proxy.js https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/proxy.js
chmod +x /usr/local/bin/proxy.js

# -------------------------------
# Download systemd service
# -------------------------------
echo "[STEP 4] Setting up ws-proxy systemd service..."
wget -O /etc/systemd/system/ws-proxy.service https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/ws-proxy.service
chmod 644 /etc/systemd/system/ws-proxy.service

# Reload systemd
systemctl daemon-reload

# Enable and start service
systemctl enable ws-proxy

# -------------------------------
# Final message
# -------------------------------
echo "========================================="
echo "WebSocket Proxy.js installation complete!"
echo "========================================="
