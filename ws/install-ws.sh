#!/bin/bash
# ==========================================
# INSTALL WEBSOCKET PROXY.JS
# ==========================================

set -e  # Exit on any error
LOG_FILE="/var/log/ws-proxy-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "Starting WebSocket Proxy.js installation..."
echo "Date: $(date)"
echo "========================================="

# -------------------------------
# Function: Log with timestamp
# -------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# -------------------------------
# Function: Check and install package
# -------------------------------
install_package() {
    local pkg=$1
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        log "Installing $pkg..."
        apt install -y "$pkg"
    else
        log "$pkg is already installed"
    fi
}

# -------------------------------
# Set non-interactive mode
# -------------------------------
export DEBIAN_FRONTEND=noninteractive

# -------------------------------
# Update & Install dependencies
# -------------------------------
log "Step 1: Updating system and installing packages..."
apt update -y
apt upgrade -y --allow-downgrades --allow-remove-essential --allow-change-held-packages

# Install essential packages
for pkg in wget curl lsof net-tools ufw build-essential; do
    install_package "$pkg"
done

# -------------------------------
# Install Node.js
# -------------------------------
log "Step 2: Checking Node.js version..."
if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -v)
    NODE_MAJOR=${NODE_VERSION#v}
    NODE_MAJOR=${NODE_MAJOR%%.*}
    
    if [[ $NODE_MAJOR -lt 16 ]]; then
        log "Node.js version too old ($NODE_VERSION). Installing Node.js 18..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt install -y nodejs
    else
        log "Node.js version is sufficient ($NODE_VERSION)"
    fi
else
    log "Node.js not found. Installing Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
fi

# Verify Node.js installation
if ! command -v node >/dev/null 2>&1; then
    log "ERROR: Node.js installation failed!"
    exit 1
fi

log "Node.js version: $(node -v)"
log "NPM version: $(npm -v)"

# -------------------------------
# Create directories
# -------------------------------
log "Step 3: Creating necessary directories..."
mkdir -p /usr/local/bin /var/log/ws-proxy /etc/ws-proxy

# -------------------------------
# Download proxy.js
# -------------------------------
log "Step 4: Downloading proxy.js..."
PROXY_JS_URL="https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/proxy.js"

if wget -q -O /usr/local/bin/proxy.js "$PROXY_JS_URL"; then
    log "proxy.js downloaded successfully"
else
    log "ERROR: Failed to download proxy.js"
    exit 1
fi

chmod +x /usr/local/bin/proxy.js

# -------------------------------
# Install npm dependencies
# -------------------------------
log "Step 5: Installing npm dependencies..."
cd /usr/local/bin
if npm install ws; then
    log "npm dependencies installed successfully"
else
    log "ERROR: Failed to install npm dependencies"
    exit 1
fi

# -------------------------------
# Download systemd service
# -------------------------------
log "Step 6: Setting up ws-proxy systemd service..."
SERVICE_URL="https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/ws-proxy.service"

if wget -q -O /etc/systemd/system/ws-proxy.service "$SERVICE_URL"; then
    log "Systemd service file downloaded successfully"
else
    log "ERROR: Failed to download systemd service file"
    exit 1
fi

chmod 644 /etc/systemd/system/ws-proxy.service

# -------------------------------
# Configure systemd service
# -------------------------------
log "Step 7: Configuring systemd service..."
systemctl daemon-reload

# Enable and start ws-proxy service
systemctl enable ws-proxy
systemctl start ws-proxy

# -------------------------------
# Verify service
# -------------------------------
log "Step 8: Verifying service status..."
sleep 5  # Give service time to start

if systemctl is-active --quiet ws-proxy; then
    log "SUCCESS: ws-proxy service is active and running"
    
    # Check if ports are listening
    log "Checking listening ports..."
    if lsof -i :1444 >/dev/null 2>&1; then
        log "Port 1444 (Stunnel) is listening"
    else
        log "WARNING: Port 1444 is not listening"
    fi
    
    if lsof -i :1445 >/dev/null 2>&1; then
        log "Port 1445 (Dropbear) is listening"
    else
        log "WARNING: Port 1445 is not listening"
    fi
else
    log "ERROR: ws-proxy service failed to start"
    log "Checking service status..."
    systemctl status ws-proxy --no-pager
    log "Check logs with: journalctl -u ws-proxy -f"
    exit 1
fi

# -------------------------------
# Create log rotation
# -------------------------------
log "Step 9: Setting up log rotation..."
cat > /etc/logrotate.d/ws-proxy << EOF
/var/log/ws-proxy-install.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

# -------------------------------
# Final message
# -------------------------------
echo "========================================="
log "WebSocket Proxy.js installation complete!"
echo "Service Info:"
echo "  - Status: systemctl status ws-proxy"
echo "  - Logs: journalctl -u ws-proxy -f"
echo "  - Restart: systemctl restart ws-proxy"
echo "Ports:"
echo "  - 1444: Stunnel WebSocket proxy"
echo "  - 1445: Dropbear WebSocket proxy"
echo "Installation log: $LOG_FILE"
echo "========================================="

# Display service status
systemctl status ws-proxy --no-pager
