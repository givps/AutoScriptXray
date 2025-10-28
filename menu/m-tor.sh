#!/bin/bash
# =========================================
# MENU TOR
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Functions ----------
tor_status() {
    if systemctl is-active --quiet tor; then
        echo -e "${green}● Tor is running${nc}"
    else
        echo -e "${red}● Tor is stopped${nc}"
    fi
}

enable_tor() {
    echo -e "${yellow}Starting Tor service...${nc}"
    systemctl start tor
    sleep 1
    tor_status
}

disable_tor() {
    echo -e "${yellow}Stopping Tor service...${nc}"
    systemctl stop tor
    sleep 1
    tor_status
}

# ---------- Menu ----------
while true; do
    clear
    echo -e ""
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}               MENU TOR                 ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e ""
    tor_status
    echo -e ""
    echo -e " ${white}1${nc}) ${green}Enable Tor${nc}"
    echo -e " ${white}2${nc}) ${red}Disable Tor${nc}"
    echo -e ""
    echo -e "${red}=========================================${nc}"
    echo -e " ${white}0${nc}) Back to Main Menu"
    echo -e " Press ${yellow}x${nc} or Ctrl+C to Exit"
    echo -e "${red}=========================================${nc}"
    echo -e ""
    read -p " Select option: " opt
    echo -e ""

    case $opt in
        1) enable_tor ;;
        2) disable_tor ;;
        0) clear ; menu ; break ;;
        x|X) exit ;;
        *) echo -e "${red}Invalid input!${nc}" ; sleep 1 ;;
    esac
done
