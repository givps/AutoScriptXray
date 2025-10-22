#!/bin/bash
# =========================================
# CHANGE DOMAIN VPS
# =========================================

# color
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

clear
echo -e "${red}=========================================${nc}"
echo -e "${green}     CUSTOM SETUP DOMAIN VPS     ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Use Domain From Script"
echo -e "${white}2${nc} Choose Your Own Domain"
echo -e "${red}=========================================${nc}"
read -rp "Choose Your Domain Installation : " dom 

if test $dom -eq 1; then
clear
rm -f /root/cf.sh
wget -q -O /root/cf.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cf.sh" && chmod +x /root/cf.sh && bash /root/cf.sh
rm -f /root/crt.sh
wget -q -O /root/crt.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/crt.sh" && chmod +x /root/crt.sh && bash /root/crt.sh
rm -f /root/slowdns.sh
wget -q -O /root/slowdns.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/slowdns/slowdns.sh" && chmod +x /root/slowdns.sh && bash /root/slowdns.sh

# done
elif test $dom -eq 2; then
read -rp "Enter Your Domain : " domen
rm -f /usr/local/etc/xray/domain /root/domain
echo "$domen" | tee /usr/local/etc/xray/domain /root/domain >/dev/null
rm -f /root/crt.sh
wget -q -O /root/crt.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/crt.sh" && chmod +x /root/crt.sh && bash /root/crt.sh
rm -f /root/slowdns.sh
wget -q -O /root/slowdns.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/slowdns/slowdns.sh" && chmod +x /root/slowdns.sh && bash /root/slowdns.sh

else 
echo "Wrong Argument"
exit 1
fi
clear

