#!/bin/bash
# =========================================
# WIREGUARD MENU
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

while true; do
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}       ⚙️  WIREGUARD VPN MENU           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e " ${white}1${nc}) Create WireGuard User"
    echo -e " ${white}2${nc}) Delete WireGuard User"
    echo -e " ${white}3${nc}) Show WireGuard Users"
    echo -e " ${white}4${nc}) Renew WireGuard User"
    echo -e " ${white}5${nc}) Restart WireGuard Service"
    echo -e "${red}=========================================${nc}"
    echo -e " ${white}0${nc}) Back to Main Menu"
    echo -e " Press ${yellow}x${nc} or Ctrl+C to Exit"
    echo -e "${red}=========================================${nc}"
    read -rp "Select menu option: " opt

    case "$opt" in
        1) wg-add ;;
        2) wg-del ;;
        3) wg-show ;;
        4) wg-renew ;;
        5)
            systemctl restart wg-quick@wg0
            if [ $? -eq 0 ]; then
                echo -e "${green}✅ WireGuard service restarted successfully!${nc}"
            else
                echo -e "${red}❌ Failed to restart WireGuard service.${nc}"
            fi
            sleep 1
            ;;
        0) menu ; break ;;
        x|X) exit 0 ;;
        *) 
            echo -e "${red}❌ Invalid option!${nc}" 
            sleep 1
            ;;
    esac
done
