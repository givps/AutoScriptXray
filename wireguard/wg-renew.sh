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

# ---------- Check prerequisites ----------
if ! command -v wg >/dev/null 2>&1; then
  echo -e "${red}❌ WireGuard is not installed!${nc}"
  m-wg
fi

if ! systemctl is-active --quiet wg-quick@wg0; then
  echo -e "${yellow}⚠️  WireGuard service is not active. Starting it now...${nc}"
  systemctl start wg-quick@wg0 || { echo -e "${red}❌ Failed to start WireGuard service!${nc}"; m-wg; }
fi

# ---------- Input ----------
read -rp "Enter username to renew: " user
if [[ -z "$user" ]]; then
  echo -e "${red}❌ Username cannot be empty!${nc}"
  m-wg
fi

# ---------- Check user existence ----------
if ! grep -q "# $user" /etc/wireguard/wg0.conf; then
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
# Remove old expiration comment and add the new one
sed -i "/# $user/d" /etc/wireguard/wg0.conf
sed -i "/PublicKey = $(grep -A3 \"# $user\" /etc/wireguard/wg0.conf | grep PublicKey | awk '{print \$3}')/i # $user | exp: $new_exp" /etc/wireguard/wg0.conf

# ---------- Restart WireGuard ----------
systemctl restart wg-quick@wg0

echo -e "${red}=========================================${nc}"
# ---------- Output ----------
echo -e "\n✅ User '${green}$user${nc}' has been renewed successfully!"
echo -e "📅 New Expiration Date: ${yellow}$new_exp${nc}"
echo -e "🔁 WireGuard service restarted.\n"
echo -e "${red}=========================================${nc}"

# ---------- Log ----------
mkdir -p /var/log/wireguard
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Renewed WireGuard user: $user (expires on $new_exp)" >> /var/log/wireguard/renew-wg.log

read -n 1 -s -r -p "Press any key to return to the menu..."
m-wg
