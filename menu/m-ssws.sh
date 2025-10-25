#!/bin/bash
# =========================================
# SHADOWSOCKS MENU
# =========================================

# ---------- Warna ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

clear
# ---------- Tampilan Menu ----------
echo -e "${red}=========================================${nc}"
echo -e "${blue}        Shadowsocks Account Menu          ${nc}"
echo -e "${red}=========================================${nc}"
echo -e ""
echo -e " ${white}1${nc}) Create Shadowsocks Account"
echo -e " ${white}2${nc}) Create Trial Shadowsocks"
echo -e " ${white}3${nc}) Extend Shadowsocks Account"
echo -e " ${white}4${nc}) Delete Shadowsocks Account"
echo -e " ${white}5${nc}) Check Shadowsocks Account"
echo -e " ${white}6${nc}) View Created Shadowsocks Log"
echo -e ""
echo -e "${red}=========================================${nc}"
echo -e " ${white}0${nc}) Back to Menu"
echo -e " Press ${yellow}x${nc} or Ctrl+C to Exit"
echo -e "${red}=========================================${nc}"
echo -e ""

# ---------- Input ----------
read -rp " Select menu : " opt
echo -e ""

# ---------- Eksekusi ----------
case $opt in
  1) clear; add-ssws ;;
  2) clear; trial-ssws ;;
  3) clear; renew-ssws ;;
  4) clear; del-ssws ;;
  5) clear; cek-ssws ;;
  6) clear; cat /var/log/create-shadowsocks.log ;;
  0) clear; menu ;;
  x|X) exit ;;
  *) echo -e "${red}You pressed it wrong!${nc}"; sleep 1; m-ssws ;;
esac
