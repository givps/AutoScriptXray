#!/bin/bash
# =========================================
# SHOW WIREGUARD USERS
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

WG_CONF="/etc/wireguard/wg0.conf"
CLIENT_DIR="/etc/wireguard/clients"

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}     🔍 Active WireGuard Accounts       ${nc}"
echo -e "${red}=========================================${nc}"

# Check if WireGuard is active
if ! systemctl is-active --quiet wg-quick@wg0; then
  echo -e "${yellow}⚠️  WireGuard service is not active!${nc}"
  echo -e "Run: ${green}systemctl start wg-quick@wg0${nc}"
  exit 1
fi

# Display header
printf "%-15s %-15s %s\n" "User" "Expired" "Latest Handshake"
echo -e "${red}-----------------------------------------${nc}"

# Check if client folder exists and has configs
shopt -s nullglob
clients=("$CLIENT_DIR"/*.conf)
shopt -u nullglob

if [[ ${#clients[@]} -eq 0 ]]; then
  echo -e "${yellow}⚠️  No WireGuard clients found.${nc}"
else
  for conf in "${clients[@]}"; do
    user=$(basename "$conf" .conf)
    exp_date=$(grep -m1 "^# Expired:" "$conf" | awk '{print $3}')
    pubkey=$(grep -m1 "^PublicKey" "$conf" | awk '{print $3}')

    if [[ -z "$pubkey" ]]; then
      last_seen="❌ No PublicKey"
    else
      handshake=$(wg show wg0 latest-handshakes | grep -w "$pubkey" | awk '{print $2}')
      if [[ -z "$handshake" || "$handshake" == "0" ]]; then
        last_seen="❌ Never"
      else
        last_seen=$(date -d @"$handshake" +"%Y-%m-%d %H:%M:%S")
      fi
    fi

    printf "%-15s %-15s %s\n" "$user" "${exp_date:-N/A}" "$last_seen"
  done
fi

echo -e "${red}=========================================${nc}"
read -n 1 -s -r -p "Press any key to return to the menu..."
clear
m-wg
