#!/bin/bash
set -euo pipefail

# =========================================
# WIREGUARD VPN SETUP SCRIPT
# =========================================

# === CONFIGURATION ===
readonly WG_PORT=51820
readonly WG_NETWORK="10.66.66.1/24"
readonly SCRIPTS_BASE_URL="https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard"

# === COLORS ===
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# === LOGGING ===
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# === ROOT CHECK ===
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root!"
   exit 1
fi

# === OS VALIDATION ===
if ! grep -qEi "debian|ubuntu" /etc/os-release; then
    log_error "Unsupported OS. Please use Debian or Ubuntu."
    exit 1
fi

# === CLEANUP OLD INSTALLATION ===
log_info "Cleaning up any existing WireGuard installation..."
systemctl stop wg-quick@wg0.service >/dev/null 2>&1 || true
systemctl disable wg-quick@wg0.service >/dev/null 2>&1 || true
systemctl reset-failed wg-quick@wg0.service >/dev/null 2>&1 || true
rm -f /usr/bin/m-wg /usr/bin/wg-add /usr/bin/wg-del /usr/bin/wg-renew /usr/bin/wg-show
apt purge -y wireguard >/dev/null 2>&1 || true
rm -rf /etc/wireguard

# === INSTALL DEPENDENCIES ===
log_info "Updating packages and installing dependencies..."
apt update -qq
apt install -y wget qrencode wireguard iproute2 iptables >/dev/null 2>&1

# === CREATE CONFIG DIRECTORY ===
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# === GENERATE SERVER KEYS ===
log_info "Generating WireGuard keys..."
umask 077
if [ -s /etc/wireguard/private.key ]; then
    log_warn "Existing key found. Keeping old key."
    privkey=$(< /etc/wireguard/private.key)
    pubkey=$(< /etc/wireguard/public.key)
else
    privkey=$(wg genkey)
    pubkey=$(echo "$privkey" | wg pubkey)
    echo "$privkey" > /etc/wireguard/private.key
    echo "$pubkey" > /etc/wireguard/public.key
fi

# === DETECT DEFAULT INTERFACE ===
log_info "Detecting default network interface..."
interface=$(ip route get 1 2>/dev/null | awk '{print $5; exit}')
interface=${interface:-$(ip -o -4 route show to default | awk '{print $5}' | head -1)}
if [ -z "$interface" ]; then
    log_error "Failed to detect default network interface!"
    exit 1
fi
log_info "Default interface: $interface"

# === CREATE WIREGUARD CONFIG ===
log_info "Creating WireGuard configuration..."
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $WG_NETWORK
ListenPort = $WG_PORT
PrivateKey = $privkey
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE; iptables-save > /etc/iptables/rules.v4
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE; iptables-save > /etc/iptables/rules.v4
SaveConfig = true
EOF

chmod 600 /etc/wireguard/wg0.conf

# === ENABLE IP FORWARDING ===
log_info "Configuring system networking..."
cat > /etc/sysctl.d/30-wireguard.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl --system >/dev/null 2>&1

# === ENABLE SERVICE ===
log_info "Enabling WireGuard service..."
systemctl daemon-reload
systemctl enable wg-quick@wg0.service >/dev/null 2>&1

if systemctl start wg-quick@wg0.service; then
    sleep 2
    if systemctl is-active --quiet wg-quick@wg0.service; then
        log_info "WireGuard service started successfully!"
    else
        log_error "WireGuard service failed to start."
        exit 1
    fi
else
    log_error "Unable to start WireGuard service."
    exit 1
fi

# === PERSIST IPTABLES ===
if [ ! -d /etc/iptables ]; then
    mkdir -p /etc/iptables
fi
iptables-save > /etc/iptables/rules.v4

# === DOWNLOAD MANAGEMENT SCRIPTS ===
log_info "Downloading WireGuard management tools..."
cd /usr/bin || exit 1
scripts=("m-wg" "wg-add" "wg-del" "wg-renew" "wg-show")
for script in "${scripts[@]}"; do
    if wget -q -O "$script" "$SCRIPTS_BASE_URL/${script}.sh"; then
        chmod +x "$script"
        log_info "Installed: $script"
    else
        log_warn "Failed to download $script"
    fi
done

# === FINAL INFORMATION ===
echo
log_info "===================================="
log_info "     WireGuard Setup Completed"
log_info "===================================="
echo "Public Key : $pubkey"
echo "Listen Port: $WG_PORT"
echo "Interface  : $interface"
echo "Network    : $WG_NETWORK"
echo
log_info "Use 'm-wg' command to manage WireGuard clients."
echo

# === END OF SCRIPT ===
