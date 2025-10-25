#!/bin/bash
# =========================================
# DELETE WIREGUARD USER + AUTO EXPIRE CLEANUP
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

# ---------- Function: Delete Specific User ----------
delete_user() {
  local user=$1
  local pubkey

  pubkey=$(grep -A 3 "# $user" "$WG_CONF" | grep PublicKey | awk '{print $3}')

  if [[ -z "$pubkey" ]]; then
    echo -e "${red}❌ User '$user' not found!${nc}"
    return 1
  fi

  # Remove from WireGuard configuration and delete client file
  sed -i "/# $user/,+4d" "$WG_CONF"
  rm -f "$CLIENT_DIR/$user.conf"

  echo -e "${green}✅ User '$user' has been successfully deleted.${nc}"
}

# ---------- Function: Auto Delete Expired Users ----------
delete_expired_users() {
  echo -e "${yellow}🕒 Checking for expired WireGuard users...${nc}"

  local today
  today=$(date +%Y-%m-%d)

  shopt -s nullglob
  for conf in "$CLIENT_DIR"/*.conf; do
    # Extract expiration date from comment line
    exp_date=$(grep -m1 "^# Expired:" "$conf" | awk '{print $3}')
    user=$(basename "$conf" .conf)

    if [[ -n "$exp_date" ]]; then
      if [[ "$exp_date" < "$today" ]]; then
        echo -e "${red}⚠️  User '$user' expired on $exp_date. Deleting...${nc}"
        delete_user "$user"
      fi
    fi
  done
  shopt -u nullglob

  echo -e "${green}✅ Expired user cleanup completed.${nc}"
}

# ---------- Menu ----------
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}    ⚙️  WireGuard User Management       ${nc}"
echo -e "${red}=========================================${nc}"
echo -e " ${white}1${nc}) Delete a specific user"
echo -e " ${white}2${nc}) Auto-delete expired users"
echo -e "${red}=========================================${nc}"
echo -e " ${white}0${nc}) Back to main menu"
echo -e " Press ${yellow}x${nc} or Ctrl+C to exit"
echo -e "${red}=========================================${nc}"
read -rp "Select an option [1-2]: " opt

case "$opt" in
  1)
    read -rp "Enter username to delete: " user
    delete_user "$user"
    ;;
  2)
    delete_expired_users
    ;;
  0)
    clear
    m-wg
    ;;
  *)
    echo -e "${red}❌ Invalid option!${nc}"
    sleep 1
    wg-del
    ;;
esac

# ---------- Restart WireGuard ----------
systemctl restart wg-quick@wg0 >/dev/null 2>&1
echo -e "${yellow}🔄 WireGuard service restarted.${nc}"

read -n 1 -s -r -p "Press any key to return to menu..."
clear
m-wg
