#!/bin/bash
set -euo pipefail

# =========================================
# SETUP WIREGUARD VPN - IMPROVED VERSION
# =========================================

# Configuration variables
readonly WG_PORT=8888
readonly WG_NETWORK="10.88.88.1/22"
readonly SCRIPTS_BASE_URL="https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Cleanup existing installation
log_info "Cleaning up existing WireGuard installation..."
rm -f /usr/bin/m-wg /usr/bin/wg-add /usr/bin/wg-del /usr/bin/wg-renew /usr/bin/wg-show

if systemctl is-active --quiet wg-quick@wg0; then
    systemctl stop wg-quick@wg0
fi

if systemctl is-enabled --quiet wg-quick@wg0; then
    systemctl disable wg-quick@wg0
fi

apt purge -y wireguard || true
rm -rf /etc/wireguard

# Update and install dependencies
log_info "Updating system and installing dependencies..."
apt update -qq
apt install -y wireguard qrencode resolvconf iproute2 iptables -qq

# Create configuration directory
mkdir -p /etc/wireguard

# Generate keys with proper permissions
log_info "Generating WireGuard keys..."
umask 077
if [ ! -s /etc/wireguard/private.key ]; then
    privkey=$(wg genkey)
    pubkey=$(echo "$privkey" | wg pubkey)
    echo "$privkey" > /etc/wireguard/private.key
    echo "$pubkey" > /etc/wireguard/public.key
else
    privkey=$(< /etc/wireguard/private.key)
    pubkey=$(< /etc/wireguard/public.key)
fi

# Detect default interface
log_info "Detecting network interface..."
interface=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
if [ -z "$interface" ]; then
    log_error "Failed to detect default network interface!"
    exit 1
fi
log_info "Default interface detected: $interface"

# Create WireGuard config
log_info "Creating WireGuard configuration..."
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $WG_NETWORK
ListenPort = $WG_PORT
PrivateKey = $privkey
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE
SaveConfig = true
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
log_info "Configuring system networking..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/30-wireguard.conf
sysctl --system >/dev/null 2>&1

# Start WireGuard service
log_info "Starting WireGuard service..."
systemctl enable wg-quick@wg0.service >/dev/null 2>&1

if systemctl start wg-quick@wg0.service; then
    sleep 2
    if systemctl is-active --quiet wg-quick@wg0.service; then
        log_info "WireGuard service started successfully!"
    else
        log_error "WireGuard service failed to start"
        exit 1
    fi
else
    log_error "Failed to start WireGuard service"
    exit 1
fi

# Download management scripts
log_info "Downloading management scripts..."
cd /usr/bin || exit 1

scripts=("m-wg" "wg-add" "wg-del" "wg-renew" "wg-show")
for script in "${scripts[@]}"; do
    if wget -q -O "$script" "$SCRIPTS_BASE_URL/${script}.sh"; then
        chmod +x "$script"
        log_info "Downloaded $script"
    else
        log_error "Failed to download $script"
    fi
done

# Display server information
echo
log_info "=== WireGuard Setup Complete ==="
echo "Public Key : $pubkey"
echo "Listen Port: $WG_PORT"
echo "Interface  : $interface"
echo "Network    : $WG_NETWORK"
echo
log_info "Use 'm-wg' to manage WireGuard clients"
