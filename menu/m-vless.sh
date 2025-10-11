#!/bin/bash
# =========================================
# SYSTEM MENU
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}            VLESS MENU          ${nc}"
echo -e "${red}=========================================${nc}"
echo -e ""
echo -e " ${white}1${nc} Create Account Vless "
echo -e " ${white}2${nc} Trial Account Vless "
echo -e " ${white}3${nc} Extending Account Vless "
echo -e " ${white}4${nc} Delete Account Vless "
echo -e " ${white}5${nc} Check User Login Vless "
echo -e " ${white}6${nc} User list created Account "
echo -e ""
echo -e "${red}=========================================${nc}"
echo -e " ${white}0${nc} Back To Menu"
echo -e   "Press ${yellow}x${nc} or Ctrl+C To-Exit"
echo -e "${red}=========================================${nc}"
echo -e ""
read -p " Select menu :  "  opt
echo -e ""
case $opt in
1) clear ; add-vless ; exit ;;
2) clear ; trial-vless ; exit ;;
3) clear ; renew-vless ; exit ;;
4) clear ; del-vless ; exit ;;
5) clear ; cek-vless ; exit ;;
6) clear ; cat /var/log/create-vless.log ; exit ;;
0) clear ; menu ; exit ;;
x) exit ;;
*) echo "You pressed it wrong " ; sleep 1 ; m-vless ;;
esac
