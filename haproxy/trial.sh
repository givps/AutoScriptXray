#!/bin/bash
# =========================================
# CREATE TRIAL SSH USER - HAPROXY WEBSOCKET VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

clear
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

openssh=`cat /root/log-install.txt | grep -w "OpenSSH" | cut -f2 -d: | awk '{print $1,$2}'`
haproxy_ssl=`cat ~/log-install.txt | grep -w "HAProxy SSH SSL WS" | cut -d: -f2 | awk '{print $1}'`
haproxy_non_ssl=`cat /root/log-install.txt | grep -w "HAProxy SSH WS" | cut -d: -f2 | awk '{print $1}'`
ssh_ssl=`cat /root/log-install.txt | grep -w "SSH/SSL" | cut -f2 -d: | awk '{print $1,$2}'`

Login=trial`</dev/urandom tr -dc X-Z0-9 | head -c4`
hari="1"
Pass=pass`</dev/urandom tr -dc X-Z0-9 | head -c4`
echo Ping Host
echo Create Akun: $Login
sleep 0.5
echo Setting Password: $Pass
sleep 0.5
clear
useradd -e `date -d "$masaaktif days" +"%Y-%m-%d"` -s /bin/false -M $Login
exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"
echo -e "$Pass\n$Pass\n"|passwd $Login &> /dev/null
PID=`ps -ef |grep -v grep | grep ws-proxy |awk '{print $2}'`

if [[ ! -z "${PID}" ]]; then
echo -e "${red}=========================================${nc}"
echo -e "${blue}            TRIAL SSH              ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "Username    : $Login"
echo -e "Password    : $Pass"
echo -e "Expired On  : $exp"
echo -e "${red}=========================================${nc}"
echo -e "IP          : $MYIP"
echo -e "Host        : $domain"
echo -e "OpenSSH     : $openssh"
echo -e "SSH WS      : $haproxy_ssl"
echo -e "SSH SSL WS  : $haproxy_non_ssl"
echo -e "SSH/SSL     : $ssh_ssl"
echo -e "UDPGW       : 7100-7900"
echo -e "${red}=========================================${nc}"
echo -e "Payload WSS"
echo -e "GET wss://bug.com HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "${red}=========================================${nc}"
echo -e "Payload WS"
echo -e "GET / HTTP/1.1[crlf]Host: $domain[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "${red}=========================================${nc}"

else

echo -e "${red}=========================================${nc}"
echo -e "${blue}            TRIAL SSH              ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "Username    : $Login"
echo -e "Password    : $Pass"
echo -e "Expired On  : $exp"
echo -e "${red}=========================================${nc}"
echo -e "IP          : $MYIP"
echo -e "Host        : $domain"
echo -e "OpenSSH     : $openssh"
echo -e "SSH WS      : $haproxy_ssl"
echo -e "SSH SSL WS  : $haproxy_non_ssl"
echo -e "SSH/SSL     : $ssh_ssl"
echo -e "UDPGW       : 7100-7900"
echo -e "${red}=========================================${nc}"
echo -e "Payload WSS"
echo -e "GET wss://bug.com HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "${red}=========================================${nc}"
echo -e "Payload WS"
echo -e "GET / HTTP/1.1[crlf]Host: $domain[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "${red}=========================================${nc}"
fi
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
