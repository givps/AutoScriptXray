#!/bin/bash
# =========================================
# CREATE WIREGUARD USER
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Check Installation ----------
if ! command -v wg >/dev/null 2>&1; then
  echo -e "${red}❌ WireGuard is not installed.${nc}"
  exit 1
fi

if ! systemctl is-active --quiet wg-quick@wg0; then
  echo -e "${yellow}⚠️ WireGuard service is not active. Starting...${nc}"
  systemctl start wg-quick@wg0 || { echo -e "${red}❌ Failed to start wg-quick@wg0${nc}"; exit 1; }
fi

# ---------- Input Username ----------
read -rp "Enter username: " user
if [[ -z "$user" ]]; then
  echo -e "${red}❌ Username cannot be empty!${nc}"
  exit 1
fi

# ---------- Prevent Duplicates ----------
mkdir -p /etc/wireguard/clients
client_config="/etc/wireguard/clients/$user.conf"
if [[ -f "$client_config" ]]; then
  echo -e "${red}❌ User '$user' already exists.${nc}"
  exit 1
fi

# ---------- Generate Keys ----------
priv_key=$(wg genkey)
pub_key=$(echo "$priv_key" | wg pubkey)
psk=$(wg genpsk)

# ---------- Auto Assign IP ----------
last_ip=$(grep AllowedIPs /etc/wireguard/wg0.conf | tail -n1 | awk '{print $3}' | cut -d'.' -f4 | cut -d'/' -f1)
if ! [[ "$last_ip" =~ ^[0-9]+$ ]]; then
    last_ip=1
fi
next_ip=$((last_ip + 1))
if [ "$next_ip" -ge 255 ]; then
    echo -e "${red}❌ IP range exceeded. Cannot assign new client IP.${nc}"
    exit 1
fi
client_ip="10.88.88.$next_ip/32"

# ---------- Get Server Info ----------
server_ip=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)
server_port=$(grep ListenPort /etc/wireguard/wg0.conf | awk '{print $3}')
server_pubkey=$(wg show wg0 public-key 2>/dev/null)

if [[ -z "$server_ip" || -z "$server_port" || -z "$server_pubkey" ]]; then
  echo -e "${red}❌ Failed to retrieve server information. Check wg0.conf or WireGuard service.${nc}"
  exit 1
fi

# ---------- Append to Server Config ----------
cat >> /etc/wireguard/wg0.conf <<EOF

# $user
[Peer]
PublicKey = $pub_key
PresharedKey = $psk
AllowedIPs = $client_ip
EOF

# ---------- Create Client Config ----------
cat > "$client_config" <<EOF
[Interface]
PrivateKey = $priv_key
Address = $client_ip
DNS = 1.1.1.1

[Peer]
PublicKey = $server_pubkey
PresharedKey = $psk
Endpoint = $server_ip:$server_port
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "$client_config"

# ---------- Apply Config ----------
wg syncconf wg0 <(wg-quick strip wg0)
if ! systemctl restart wg-quick@wg0; then
    echo -e "${red}❌ Failed to restart wg-quick@wg0. Check configuration.${nc}"
    exit 1
fi

# ---------- Output ----------
echo -e "${red}=========================================${nc}"
echo -e "${green}✅ WireGuard user '$user' has been created successfully!${nc}"
echo "📡 Client IP  : $client_ip"
echo "🌍 Endpoint   : $server_ip:$server_port"
echo "📄 Config     : $client_config"
echo -e "${red}=========================================${nc}"

# ---------- QR Code ----------
if command -v qrencode >/dev/null 2>&1; then
  echo -e "${yellow}📷 QR Code (scan in WireGuard app):${nc}"
  qrencode -t ansiutf8 < "$client_config"
fi

# ---------- Save Log ----------
mkdir -p /var/log
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created: $user ($client_ip)"
  cat "$client_config"
  echo
} >> /var/log/create-wg.log

read -n 1 -s -r -p "Press any key to return to menu..."
clear
m-wg
