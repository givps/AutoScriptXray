#!/bin/bash
set -euo pipefail
# =========================================
# CREATE WIREGUARD USER
# =========================================

# ---------- Colors ----------
red='\e[1;31m'; green='\e[0;32m'; yellow='\e[1;33m'; blue='\e[1;34m'; nc='\e[0m'

# ---------- Functions ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

# ---------- Check Installation ----------
if ! command -v wg >/dev/null 2>&1; then
  log_error "WireGuard is not installed."
  exit 1
fi

if ! systemctl is-active --quiet wg-quick@wg0; then
  log_warn "WireGuard service is not active. Starting..."
  systemctl daemon-reload
  if ! systemctl start wg-quick@wg0; then
    log_error "Failed to start wg-quick@wg0"
    exit 1
  fi
  sleep 2
fi

# ---------- Input Username ----------
read -rp "Enter username: " user
if [[ -z "$user" ]]; then
  log_error "Username cannot be empty!"
  exit 1
fi
user=$(echo "$user" | tr '[:upper:]' '[:lower:]')

if [[ ! "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
  log_error "Username can only contain letters, numbers, and underscores"
  exit 1
fi

# ---------- Prevent Duplicates ----------
mkdir -p /etc/wireguard/clients
client_config="/etc/wireguard/clients/$user.conf"
if [[ -f "$client_config" ]]; then
  log_error "User '$user' already exists."
  exit 1
fi

# ---------- Generate Keys ----------
log_info "Generating cryptographic keys..."
priv_key=$(wg genkey)
pub_key=$(echo "$priv_key" | wg pubkey)
psk=$(wg genpsk)

# ---------- Dynamic IP Allocation ----------
find_available_ip() {
    local base_network
    base_network=$(grep -m1 Address /etc/wireguard/wg0.conf | cut -d'=' -f2 | tr -d ' ' | cut -d'/' -f1 | cut -d'.' -f1-3)
    local used_ips=()

    used_ips+=($(wg show wg0 allowed-ips 2>/dev/null | awk '{print $2}' | cut -d'.' -f4 | cut -d'/' -f1))
    used_ips+=($(grep AllowedIPs /etc/wireguard/wg0.conf | awk '{print $3}' | cut -d'.' -f4 | cut -d'/' -f1))
    used_ips=($(printf "%s\n" "${used_ips[@]}" | sort -nu))

    for i in {2..254}; do
        if [[ ! " ${used_ips[*]} " =~ " $i " ]]; then
            echo "$base_network.$i"
            return 0
        fi
    done
    log_error "No available IP addresses in range."
    exit 1
}

client_ip="$(find_available_ip)/32"
log_info "Assigned IP: $client_ip"

# ---------- Server Info ----------
log_info "Retrieving server information..."
server_ip=$(curl -s -4 ipv4.icanhazip.com || curl -s -4 ifconfig.me || curl -s -4 icanhazip.com)
server_ip=$(echo "$server_ip" | tr -d '\r')
server_port=$(grep -m1 ListenPort /etc/wireguard/wg0.conf | awk '{print $3}')
server_pubkey=$(wg show wg0 | awk '/public key/ {print $3; exit}')

if [[ -z "$server_ip" ]]; then
  log_warn "Could not detect public IP automatically"
  read -rp "Please enter server public IP: " server_ip
  if [[ -z "$server_ip" ]]; then
    log_error "Server IP is required"
    exit 1
  fi
fi

if [[ -z "$server_port" || -z "$server_pubkey" ]]; then
  log_error "Failed to retrieve server configuration. Check wg0.conf or WireGuard service."
  exit 1
fi

# ---------- Backup Original Config ----------
config_backup="/etc/wireguard/wg0.conf.backup.$(date +%Y%m%d_%H%M%S)"
cp /etc/wireguard/wg0.conf "$config_backup"
log_info "Backup created: $config_backup"

# ---------- Append to Server Config ----------
log_info "Adding new peer to server config..."
cat >> /etc/wireguard/wg0.conf <<EOF

# $user - added on $(date '+%Y-%m-%d %H:%M:%S')
[Peer]
PublicKey = $pub_key
PresharedKey = $psk
AllowedIPs = $client_ip
EOF

# ---------- Create Client Config ----------
log_info "Creating client configuration..."
cat > "$client_config" <<EOF
[Interface]
PrivateKey = $priv_key
Address = ${client_ip%/*}/24
DNS = 1.1.1.1,8.8.8.8,9.9.9.9

[Peer]
PublicKey = $server_pubkey
PresharedKey = $psk
Endpoint = $server_ip:$server_port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 "$client_config"

# ---------- Apply Config (Safe Reload) ----------
log_info "Applying configuration changes..."
if wg-quick strip wg0 >/tmp/wg-temp.conf 2>/dev/null && wg syncconf wg0 /tmp/wg-temp.conf; then
    log_success "Configuration applied successfully (live reload)"
else
    log_warn "Live reload failed — restarting service..."
    if ! systemctl restart wg-quick@wg0; then
        log_error "Failed to restart WireGuard. Restoring backup..."
        cp "$config_backup" /etc/wireguard/wg0.conf
        rm -f "$client_config"
        exit 1
    fi
fi

# ---------- Verify ----------
if wg show wg0 | grep -q "$pub_key"; then
    log_success "Peer verified in running configuration."
else
    log_warn "Peer not detected live, but config updated successfully."
fi

# ---------- Output ----------
echo
echo -e "${green}=========================================${nc}"
log_success "WireGuard user '$user' created successfully!"
echo "👤 Username   : $user"
echo "📍 Client IP  : $client_ip"
echo "🌍 Endpoint   : $server_ip:$server_port"
echo "📁 Config file: $client_config"
echo -e "${green}=========================================${nc}"
echo

# ---------- QR Code ----------
if command -v qrencode >/dev/null 2>&1; then
  echo -e "${yellow}📷 QR Code (scan in WireGuard app):${nc}"
  qrencode -t ansiutf8 < "$client_config"
  echo
fi

# ---------- Display Config ----------
echo -e "${yellow}📄 Client configuration content:${nc}"
cat "$client_config"
echo

# ---------- Log Creation ----------
mkdir -p /var/log/wireguard
chmod 700 /var/log/wireguard
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created: $user ($client_ip)"
  echo "PublicKey: $pub_key"
  echo "Endpoint: $server_ip:$server_port"
  echo "---"
} >> /var/log/wireguard/user-creation.log
chmod 600 /var/log/wireguard/user-creation.log

# ---------- Final Notes ----------
log_info "To revoke this user, run: wg-del $user"
log_info "To show all users, run: wg-show"

# ---------- Return to Menu ----------
if command -v m-wg >/dev/null 2>&1; then
  read -n 1 -s -r -p "Press any key to return to menu..."
  clear
  m-wg
fi
