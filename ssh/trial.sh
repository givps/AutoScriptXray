#!/bin/bash
# =========================================
# CREATE TRIAL SSH USER
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
#sldomain=$(cat /root/nsdomain)
#slkey=$(cat /etc/slowdns/server.pub)

openssh=`cat /root/log-install.txt | grep -w "OpenSSH" | cut -f2 -d: | awk '{print $1,$2}'`
db=`cat /root/log-install.txt | grep -w "Dropbear" | cut -f2 -d: | awk '{print $1,$2}'`
sshws=`cat /root/log-install.txt | grep -w "SSH Websocket" | cut -f2 -d: | awk '{print $1,$2}'`
sshwsssl=`cat /root/log-install.txt | grep -w "SSH SSL Websocket" | cut -f2 -d: | awk '{print $1,$2}'`
ssl=`cat /root/log-install.txt | grep -w "Stunnel4" | cut -f2 -d: | awk '{print $1,$2,$3,$4}'`

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
echo -e "Dropbear    : $db"
echo -e "SSH WS      : $sshws"
echo -e "SSH SSL WS  : $sshwsssl"
echo -e "SSH/SSL     : $ssl"
echo -e "UDPGW       : 7100-7900"
#echo -e "Port NS     : ALL Port"
#echo -e "Nameserver  : $sldomain"
#echo -e "Pubkey      : $slkey"
#echo -e "UDP Custom  : 1-65350"
echo -e "${red}=========================================${nc}"
echo -e "${blue}        TRIAL OpenVPN Account           ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "Username    : $Login"
echo -e "Password    : $Pass"
echo -e "Expired On  : $exp"
echo -e "${red}=========================================${nc}"
echo -e "openvpn tcp  : https://$domain/openvpn/tcp.ovpn"
echo -e "openvpn udp  : https://$domain/openvpn/udp.ovpn"
echo -e "openvpn ssl  : https://$domain/openvpn/ssl.ovpn"
echo -e "openvpn zip  : https://$domain/openvpn/ovpn.zip"
echo -e "${red}=========================================${nc}"
echo -e "Payload WSS"
echo -e "
GET wss://bug.com HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
"
echo -e "${red}=========================================${nc}"
echo -e "Payload WS"
echo -e "
GET / HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
"
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
echo -e "Dropbear    : $db"
echo -e "SSH WS      : $sshws"
echo -e "SSH SSL WS  : $sshwsssl"
echo -e "SSH/SSL     : $ssl"
echo -e "UDPGW       : 7100-7900"
#echo -e "Port NS     : ALL Port"
#echo -e "Nameserver  : $sldomain"
#echo -e "Pubkey      : $slkey"
#echo -e "UDP Custom  : 1-65350"
echo -e "${red}=========================================${nc}"
echo -e "${blue}        TRIAL OpenVPN Account           ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "Username    : $Login"
echo -e "Password    : $Pass"
echo -e "Expired On  : $exp"
echo -e "${red}=========================================${nc}"
echo -e "openvpn tcp  : https://$domain/openvpn/tcp.ovpn"
echo -e "openvpn udp  : https://$domain/openvpn/udp.ovpn"
echo -e "openvpn ssl  : https://$domain/openvpn/ssl.ovpn"
echo -e "openvpn zip  : https://$domain/openvpn/ovpn.zip"
echo -e "${red}=========================================${nc}"
echo -e "Payload WSS"
echo -e "
GET wss://bug.com HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
"
echo -e "${red}=========================================${nc}"
echo -e "Payload WS"
echo -e "
GET / HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
"
echo -e "${red}=========================================${nc}"
fi
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
