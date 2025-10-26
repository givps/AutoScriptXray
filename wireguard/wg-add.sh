#!/bin/bash
# =========================================
# CREATE WIREGUARD USER - IMPROVED VERSION
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

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

# Validasi username (hanya huruf, angka, underscore)
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

# ---------- Improved IP Assignment ----------
find_available_ip() {
    local base_network="10.88.88"
    local used_ips=()
    
    # Get all currently used IPs
    if command -v wg >/dev/null 2>&1; then
        # Try to get from running interface first
        used_ips+=($(wg show wg0 allowed-ips 2>/dev/null | awk '{print $2}' | cut -d'.' -f4 | cut -d'/' -f1))
    fi
    
    # Also check config file
    if [[ -f /etc/wireguard/wg0.conf ]]; then
        used_ips+=($(grep AllowedIPs /etc/wireguard/wg0.conf | awk '{print $3}' | cut -d'.' -f4 | cut -d'/' -f1))
    fi
    
    # Remove duplicates and sort
    used_ips=($(printf "%s\n" "${used_ips[@]}" | sort -nu))
    
    # Find first available IP starting from 2
    for i in {2..254}; do
        if [[ ! " ${used_ips[@]} " =~ " $i " ]]; then
            echo "$i"
            return 0
        fi
    done
    
    log_error "No available IP addresses in range"
    exit 1
}

ip_suffix=$(find_available_ip)
client_ip="10.88.88.$ip_suffix/32"

log_info "Assigned IP: $client_ip"

# ---------- Get Server Info ----------
log_info "Retrieving server information..."
server_ip=$(curl -s -4 ipv4.icanhazip.com || curl -s -4 ifconfig.me || curl -s -4 icanhazip.com)
server_port=$(grep ListenPort /etc/wireguard/wg0.conf | awk '{print $3}')
server_pubkey=$(wg show wg0 public-key 2>/dev/null)

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
log_info "Config backed up to: $config_backup"

# ---------- Append to Server Config ----------
log_info "Updating server configuration..."
cat >> /etc/wireguard/wg0.conf <<EOF

# $user
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
Address = 10.88.88.$ip_suffix/24
DNS = 1.1.1.1,8.8.8.8

[Peer]
PublicKey = $server_pubkey
PresharedKey = $psk
Endpoint = $server_ip:$server_port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 "$client_config"

# ---------- Apply Config ----------
log_info "Applying configuration changes..."
if wg syncconf wg0 <(wg-quick strip wg0 2>/dev/null); then
    log_success "Configuration applied successfully (live reload)"
else
    log_warn "Live reload failed, restarting service..."
    if ! systemctl restart wg-quick@wg0; then
        log_error "Failed to restart WireGuard service. Restoring backup..."
        cp "$config_backup" /etc/wireguard/wg0.conf
        rm -f "$client_config"
        exit 1
    fi
fi

# ---------- Verify Installation ----------
if wg show wg0 | grep -q "$pub_key"; then
    log_success "Peer verified in running configuration"
else
    log_warn "Peer not found in running configuration but config file was updated"
fi

# ---------- Output ----------
echo
echo -e "${green}=========================================${nc}"
log_success "WireGuard user '$user' has been created successfully!"
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

# ---------- Display Config Content ----------
echo -e "${yellow}📄 Client config content:${nc}"
cat "$client_config"
echo

# ---------- Save Log ----------
mkdir -p /var/log/wireguard
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created: $user ($client_ip)"
  echo "PublicKey: $pub_key"
  echo "Endpoint: $server_ip:$server_port"
  echo "---"
} >> /var/log/wireguard/user-creation.log

# ---------- Final Instructions ----------
log_info "To revoke this user, run: wg-del $user"
log_info "To show all users, run: wg-show"

read -n 1 -s -r -p "Press any key to return to menu..."
clear
m-wg
