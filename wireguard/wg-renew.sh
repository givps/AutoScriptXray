#!/bin/bash
# =========================================
# RENEW WIREGUARD USER
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

WG_CONF="/etc/wireguard/wg0.conf"
LOG_DIR="/var/log/wireguard"
mkdir -p "$LOG_DIR"

# ---------- Check prerequisites ----------
if ! command -v wg >/dev/null 2>&1; then
  echo -e "${red}❌ WireGuard is not installed!${nc}"
  m-wg
fi

if ! systemctl is-active --quiet wg-quick@wg0; then
  echo -e "${yellow}⚠️ WireGuard service is not active. Starting it now...${nc}"
  systemctl start wg-quick@wg0 || { echo -e "${red}❌ Failed to start WireGuard service!${nc}"; m-wg; }
fi

# ---------- Input ----------
read -rp "Enter username to renew: " user
if [[ -z "$user" ]]; then
  echo -e "${red}❌ Username cannot be empty!${nc}"
  m-wg
fi

# ---------- Check user existence ----------
if ! grep -q "# $user" "$WG_CONF"; then
  echo -e "${red}❌ User '$user' not found!${nc}"
  m-wg
fi

# ---------- Ask new expiration ----------
read -rp "Enter new expiration date (YYYY-MM-DD): " new_exp
if ! date -d "$new_exp" >/dev/null 2>&1; then
  echo -e "${red}❌ Invalid date format! Use YYYY-MM-DD.${nc}"
  m-wg
fi

# ---------- Update expiration ----------
# Cari baris PublicKey user
pubkey=$(grep -A3 "# $user" "$WG_CONF" | grep PublicKey | awk '{print $3}')
if [[ -z "$pubkey" ]]; then
    echo -e "${red}❌ Could not find PublicKey for user '$user'.${nc}"
    m-wg
fi

# Hapus komentar lama user jika ada
sed -i "/# $user/d" "$WG_CONF"
# Tambahkan komentar baru tepat sebelum PublicKey user
sed -i "/PublicKey = $pubkey/i # $user | Exp: $new_exp" "$WG_CONF"

# ---------- Restart WireGuard ----------
systemctl restart wg-quick@wg0

# ---------- Output ----------
echo -e "${red}=========================================${nc}"
echo -e "${green}✅ User '$user' has been renewed successfully!${nc}"
echo -e "📅 New Expiration Date: ${yellow}$new_exp${nc}"
echo -e "🔁 WireGuard service restarted."
echo -e "${red}=========================================${nc}"

# ---------- Log ----------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Renewed WireGuard user: $user (expires on $new_exp)" >> "$LOG_DIR/renew-wg.log"

read -n 1 -s -r -p "Press any key to return to the menu..."
m-wg
