#!/bin/bash
# =========================================
# SSH MENU
# =========================================

# ---------- Warna ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}              SSH MENU                   ${nc}"
echo -e "${red}=========================================${nc}"
echo -e ""
echo -e " ${white}1${nc}) Create SSH & WS Account"
echo -e " ${white}2${nc}) Trial SSH & WS Account"
echo -e " ${white}3${nc}) Renew SSH & WS Account"
echo -e " ${white}4${nc}) Delete SSH & WS Account"
echo -e " ${white}5${nc}) List Member SSH & WS"
echo -e " ${white}6${nc}) Delete Expired SSH & WS"
echo -e " ${white}7${nc}) Set up Autokill SSH"
echo -e " ${white}8${nc}) View Created User Logs"
echo -e " ${white}9${nc}) Lock User Account"
echo -e " ${white}10${nc}) BadVPN Control"
echo -e ""
echo -e "${red}=========================================${nc}"
echo -e " ${white}0${nc} Back to Menu"
echo -e " Press ${yellow}x${nc} or Ctrl+C to Exit"
echo -e "${red}=========================================${nc}"
echo -e ""

# ---------- Input ----------
read -rp " Select menu: " opt
echo -e ""

# ---------- Eksekusi ----------
case $opt in
  1) clear; usernew ;;
  2) clear; trial ;;
  3) clear; renew ;;
  4) clear; delete ;;
  5) clear; member ;;
  6) clear; autodelete ;;
  7) clear; autokill ;;
  8) clear; cat /var/log/create-ssh.log ;;
  9) clear; lock-unlock ;;
  10) clear; m-badvpn ;;
  0) clear; menu ;;
  x|X) exit ;;
  *) echo -e "${red}You pressed it wrong!${nc}"; sleep 1; m-sshovpn ;;
esac
