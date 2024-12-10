#!/bin/bash
# Quick Setup | Script Setup Manager
# Edition : Stable Edition 1.0
# Author  : givps
# The MIT License (MIT)
# (C) Copyright 2023
# =========================================
MYIP=$(curl -sS ipv4.icanhazip.com)
echo "Checking VPS"
clear
# Color Validation
DF='\e[39m'
Bold='\e[1m'
Blink='\e[5m'
yell='\e[33m'
red='\e[31m'
green='\e[32m'
blue='\e[34m'
PURPLE='\e[35m'
cyan='\e[36m'
Lred='\e[91m'
Lgreen='\e[92m'
Lyellow='\e[93m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
BPurple='\e[1;35m'
BCyan='\e[1;36m'
NC='\e[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
LIGHT='\033[0;37m'
# VPS Information
#Domain
domain=$(cat /etc/xray/domain)
#Status certificate
modifyTime=$(stat $HOME/.acme.sh/${domain}_ecc/${domain}.key | sed -n '7,6p' | awk '{print $2" "$3" "$4" "$5}')
modifyTime1=$(date +%s -d "${modifyTime}")
currentTime=$(date +%s)
stampDiff=$(expr ${currentTime} - ${modifyTime1})
days=$(expr ${stampDiff} / 86400)
remainingDays=$(expr 90 - ${days})
tlsStatus=${remainingDays}
if [[ ${remainingDays} -le 0 ]]; then
	tlsStatus="expired"
fi
# OS Uptime
uptime="$(uptime -p | cut -d " " -f 2-10)"
# Download
#Download/Upload today
dtoday="$(vnstat -i eth0 | grep "today" | awk '{print $2" "substr ($3, 1, 1)}')"
utoday="$(vnstat -i eth0 | grep "today" | awk '{print $5" "substr ($6, 1, 1)}')"
ttoday="$(vnstat -i eth0 | grep "today" | awk '{print $8" "substr ($9, 1, 1)}')"
#Download/Upload yesterday
dyest="$(vnstat -i eth0 | grep "yesterday" | awk '{print $2" "substr ($3, 1, 1)}')"
uyest="$(vnstat -i eth0 | grep "yesterday" | awk '{print $5" "substr ($6, 1, 1)}')"
tyest="$(vnstat -i eth0 | grep "yesterday" | awk '{print $8" "substr ($9, 1, 1)}')"
#Download/Upload current month
dmon="$(vnstat -i eth0 -m | grep "`date +"%b '%y"`" | awk '{print $3" "substr ($4, 1, 1)}')"
umon="$(vnstat -i eth0 -m | grep "`date +"%b '%y"`" | awk '{print $6" "substr ($7, 1, 1)}')"
tmon="$(vnstat -i eth0 -m | grep "`date +"%b '%y"`" | awk '{print $9" "substr ($10, 1, 1)}')"
# user
Exp2=$"Lifetime"
Name=$"VIP-MEMBERS"
# Getting CPU Information
cpu_usage1="$(ps aux | awk 'BEGIN {sum=0} {sum+=$3}; END {print sum}')"
cpu_usage="$((${cpu_usage1/\.*} / ${corediilik:-1}))"
cpu_usage+=" %"
ISP=$(curl -s https://ipapi.co/org | cut -d " " -f 2-10 )
CITY=$(curl -s https://ipinfo.io/city )
#WKT=$(curl -s ipinfo.io/timezone?token=ce3da57536810d )
DAY=$(date +%A)
DATE=$(date +%m/%d/%Y)
DATE2=$(date -R | cut -d " " -f -5)
IPVPS=$(curl -s ipv4.icanhazip.com )
LOC=$(curl -s https://ipapi.co/country_code )
cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo )
cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
freq=$( awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo )
tram=$( free -m | awk 'NR==2 {print $2}' )
uram=$( free -m | awk 'NR==2 {print $3}' )
fram=$( free -m | awk 'NR==2 {print $4}' )
clear 
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;34m                      VPS INFO                    \e[0m"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;32m OS            \e[0m: "`hostnamectl | grep "Operating System" | cut -d ' ' -f5-`	
echo -e "\e[1;32m Uptime        \e[0m: $uptime"
echo -e "\e[1;32m Public IP     \e[0m: $IPVPS"
echo -e "\e[1;32m CITY          \e[0m: $CITY"
echo -e "\e[1;32m Country       \e[0m: $LOC"
echo -e "\e[1;32m ASN           \e[0m: $ISP"
echo -e "\e[1;32m DOMAIN        \e[0m: $domain"
echo -e "\e[1;32m DATE & TIME   \e[0m: $DATE2"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;34m                      RAM INFO                    \e[0m"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e ""
echo -e "\e[1;32m RAM USED   \e[0m: $uram MB"	
echo -e "\e[1;32m RAM TOTAL  \e[0m: $tram MB"
echo -e ""
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;34m                       MENU                       \e[0m"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e   ""
echo -e "\e[1;36m 1 \e[0m: Menu SSH"
echo -e "\e[1;36m 2 \e[0m: Menu Vmess"
echo -e "\e[1;36m 3 \e[0m: Menu Vless"
echo -e "\e[1;36m 4 \e[0m: Menu Trojan"
echo -e "\e[1;36m 5 \e[0m: Menu Shadowsocks"
echo -e "\e[1;36m 6 \e[0m: Menu Setting"
echo -e "\e[1;36m 7 \e[0m: Status Service"
echo -e "\e[1;36m 8 \e[0m: Clear RAM Cache"
echo -e "\e[1;36m 9 \e[0m: Reboot VPS"
echo -e "\e[1;36m x \e[0m: Exit Script and to start again use: menu"
echo -e   ""
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;32m Client Name \e[0m: $Name"
echo -e "\e[1;32m Expired     \e[0m: $Exp2"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e   ""
echo -e "\e[1;36m --------------------t.me/givpn_grup-------------------\e[0m"
echo -e   ""
read -p " Select menu :  "  opt
echo -e   ""
case $opt in
1) clear ; m-sshovpn ;;
2) clear ; m-vmess ;;
3) clear ; m-vless ;;
4) clear ; m-trojan ;;
5) clear ; m-ssws ;;
6) clear ; m-system ;;
7) clear ; running ;;
8) clear ; clearcache ;;
9) clear ; reboot ; /sbin/reboot ;;
x) exit ;;
*) echo "You pressed it wrong " ; sleep 1 ; menu ;;
esac

