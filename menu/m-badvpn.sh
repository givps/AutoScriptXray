#!/bin/bash
# =========================================
# BadVPN Control Menu
# =========================================

# ---------- Warna ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

while true; do
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}          BADVPN CONTROL MENU            ${nc}"
    echo -e "${red}=========================================${nc}"
    echo
    echo -e "${white} [1]${nc} Start BadVPN UDPGW Service"
    echo -e "${white} [2]${nc} Stop BadVPN UDPGW Service"
    echo -e "${white} [3]${nc} Check BadVPN Service Status"
    echo
    echo -e "${white} [0]${nc} Back to Menu"
    echo
    echo -e "${red}=========================================${nc}"
    echo
    read -rp "Select an option [0-3]: " opt
    clear

    case $opt in
        1)
            echo -e "${blue}Starting BadVPN UDPGW...${nc}"
            if command -v udpgw-start >/dev/null 2>&1; then
                udpgw-start
                echo -e "${green}BadVPN started successfully.${nc}"
            else
                echo -e "${red}Error: udpgw-start command not found!${nc}"
            fi
            echo
            read -n 1 -s -r -p "Press any key to return to menu..."
            ;;
        2)
            echo -e "${blue}Stopping BadVPN UDPGW...${nc}"
            if command -v udpgw-stop >/dev/null 2>&1; then
                udpgw-stop
                echo -e "${green}BadVPN stopped.${nc}"
            else
                echo -e "${red}Error: udpgw-stop command not found!${nc}"
            fi
            echo
            read -n 1 -s -r -p "Press any key to return to menu..."
            ;;
        3)
            echo -e "${blue}Checking BadVPN Status...${nc}"
            echo
            if command -v udpgw-status >/dev/null 2>&1; then
                udpgw-status
            else
                echo -e "${red}Error: udpgw-status command not found!${nc}"
            fi
            echo
            read -n 1 -s -r -p "Press any key to return to menu..."
            ;;
        0)
            echo -e "${green}Returning to SSH & VPN Menu...${nc}"
            sleep 1
            m-sshovpn
            exit 0
            ;;
        *)
            echo -e "${red}Invalid option!${nc}"
            sleep 1
            ;;
    esac
done
