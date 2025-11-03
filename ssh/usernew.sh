#!/bin/bash
# =========================================
# CREATE SSH USER
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

echo -e "${red}=========================================${nc}"
echo -e "${blue}            SSH Account            ${nc}"
echo -e "${red}=========================================${nc}"
read -p "Username : " Login
read -p "Password : " Pass
read -p "Expired (day): " masaaktif

sleep 1
clear
useradd -e `date -d "$masaaktif days" +"%Y-%m-%d"` -s /bin/false -M $Login
exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"
echo -e "$Pass\n$Pass\n"|passwd $Login &> /dev/null
PID=`ps -ef |grep -v grep | grep ws-proxy |awk '{print $2}'`

if [[ ! -z "${PID}" ]]; then
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "${blue}            SSH Account            ${nc}" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Username    : $Login" | tee -a /var/log/create-ssh.log
echo -e "Password    : $Pass" | tee -a /var/log/create-ssh.log
echo -e "Expired On  : $exp" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "IP          : $MYIP" | tee -a /var/log/create-ssh.log
echo -e "Host        : $domain" | tee -a /var/log/create-ssh.log
echo -e "OpenSSH     : $openssh" | tee -a /var/log/create-ssh.log
echo -e "Dropbear    : $db" | tee -a /var/log/create-ssh.log
echo -e "SSH WS      : $sshws" | tee -a /var/log/create-ssh.log
echo -e "SSH SSL WS  : $sshwsssl" | tee -a /var/log/create-ssh.log
echo -e "SSH/SSL     : $ssl" | tee -a /var/log/create-ssh.log
echo -e "UDPGW       : 7100-7900" | tee -a /var/log/create-ssh.log
#echo -e "Port NS     : ALL Port" | tee -a /var/log/create-ssh.log
#echo -e "Nameserver  : $sldomain" | tee -a /var/log/create-ssh.log
#echo -e "Pubkey      : $slkey" | tee -a /var/log/create-ssh.log
#echo -e "UDP Custom  : 1-65350" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "${blue}            OpenVPN Account            ${nc}" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Username    : $Login" | tee -a /var/log/create-ssh.log
echo -e "Password    : $Pass" | tee -a /var/log/create-ssh.log
echo -e "Expired On  : $exp" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "openvpn tcp  : https://$domain/openvpn/tcp.ovpn" | tee -a /var/log/create-ssh.log
echo -e "openvpn udp  : https://$domain/openvpn/udp.ovpn" | tee -a /var/log/create-ssh.log
echo -e "openvpn ssl  : https://$domain/openvpn/ssl.ovpn" | tee -a /var/log/create-ssh.log
echo -e "openvpn zip  : https://$domain/openvpn/ovpn.zip" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Payload WSS" | tee -a /var/log/create-ssh.log
echo -e "
GET wss://bug.com HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Payload WS" | tee -a /var/log/create-ssh.log
echo -e "
GET / HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
else

echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "${blue}            SSH Account            ${nc}" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Username    : $Login" | tee -a /var/log/create-ssh.log
echo -e "Password    : $Pass" | tee -a /var/log/create-ssh.log
echo -e "Expired On  : $exp" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "IP          : $MYIP" | tee -a /var/log/create-ssh.log
echo -e "Host        : $domain" | tee -a /var/log/create-ssh.log
echo -e "OpenSSH     : $openssh" | tee -a /var/log/create-ssh.log
echo -e "Dropbear    : $db" | tee -a /var/log/create-ssh.log
echo -e "SSH WS      : $sshws" | tee -a /var/log/create-ssh.log
echo -e "SSH SSL WS  : $sshwsssl" | tee -a /var/log/create-ssh.log
echo -e "SSH/SSL     : $ssl" | tee -a /var/log/create-ssh.log
echo -e "UDPGW       : 7100-7900" | tee -a /var/log/create-ssh.log
#echo -e "Port NS     : ALL Port" | tee -a /var/log/create-ssh.log
#echo -e "Nameserver  : $sldomain" | tee -a /var/log/create-ssh.log
#echo -e "Pubkey      : $slkey" | tee -a /var/log/create-ssh.log
#echo -e "UDP Custom  : 1-65350" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "${blue}            OpenVPN Account            ${nc}" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Username    : $Login" | tee -a /var/log/create-ssh.log
echo -e "Password    : $Pass" | tee -a /var/log/create-ssh.log
echo -e "Expired On  : $exp" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "openvpn tcp  : https://$domain/openvpn/tcp.ovpn" | tee -a /var/log/create-ssh.log
echo -e "openvpn udp  : https://$domain/openvpn/udp.ovpn" | tee -a /var/log/create-ssh.log
echo -e "openvpn ssl  : https://$domain/openvpn/ssl.ovpn" | tee -a /var/log/create-ssh.log
echo -e "openvpn zip  : https://$domain/openvpn/ovpn.zip" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Payload WSS" | tee -a /var/log/create-ssh.log
echo -e "
GET wss://bug.com HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
echo -e "Payload WS" | tee -a /var/log/create-ssh.log
echo -e "
GET / HTTP/1.1[crlf] Host: ${domain}[crlf] Upgrade: websocket[crlf] Connection: Upgrade[crlf]
" | tee -a /var/log/create-ssh.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-ssh.log
fi
echo "" | tee -a /var/log/create-ssh.log
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
