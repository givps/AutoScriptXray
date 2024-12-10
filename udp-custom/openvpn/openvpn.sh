#!/bin/bash
# Quick Setup | Script Setup Manager
# Edition : Stable Edition 1.0
# Author  : givps
# The MIT License (MIT)
# (C) Copyright 2023
# =========================================
# pewarna hidup
BGreen='\e[1;32m'
NC='\e[0m'
domain=$(cat /etc/xray/domain)
echo "$domain" > /root/domain
clear
MYIP=$(wget -qO- ipv4.icanhazip.com);
MYIP2="s/xxxxxxxxx/$MYIP/g";
# // install squid for ubuntu 18/20
apt -y install squid3

# install squid for debian 11
sleep 1
echo "\e[1;32m Squid Download Process.. \e[0m"
apt -y install squid
wget -O /etc/squid/squid.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/openvpn/squid3.conf"
sed -i $MYIP2 /etc/squid/squid.conf

# // OpenVPN
sleep 1
echo "\e[1;32m OpenVPN Download Process.. \e[0m"
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/openvpn/vpn.sh &&  chmod +x vpn.sh && ./vpn.sh

cd
chown -R www-data:www-data /home/vps/public_html
sleep 0.5
echo -e "$BGreen[SERVICE]$NC Restart All service SSH & OVPN"
/etc/init.d/nginx restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting nginx"
/etc/init.d/openvpn restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting cron "
/etc/init.d/ssh restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting ssh "
/etc/init.d/dropbear restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting dropbear "
/etc/init.d/fail2ban restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting fail2ban "
/etc/init.d/stunnel4 restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting stunnel4 "
/etc/init.d/vnstat restart >/dev/null 2>&1
sleep 0.5
echo -e "[ ${BGreen}ok${NC} ] Restarting vnstat "
/etc/init.d/squid restart >/dev/null 2>&1
clear
echo ""
echo "=================================================================="  | tee -a log-install.txt
echo "-----------------------------------------Service Information----------------------------------------------"  | tee -a log-install.txt
echo "=================================================================="  | tee -a log-install.txt
echo ""
echo "   >>> Service & Port"  | tee -a log-install.txt
echo "   - OpenSSH                  : 22"  | tee -a log-install.txt
echo "   - OpenVPN TCP          : 1194"  | tee -a log-install.txt
echo "   - OpenVPN UDP          : 2200"  | tee -a log-install.txt
echo "   - Squid Proxy              : 3128, 8000"  | tee -a log-install.txt
echo "   - SSH Websocket            : 80" | tee -a log-install.txt
echo "   - SSH SSL Websocket        : 443" | tee -a log-install.txt
echo "   - Stunnel4                 : 222, 777" | tee -a log-install.txt
echo "   - Dropbear                 : 109, 143" | tee -a log-install.txt
echo "   - Badvpn                   : 7100-7900" | tee -a log-install.txt
echo "   - Nginx                    : 81" | tee -a log-install.txt
echo "   - Vmess WS TLS             : 443" | tee -a log-install.txt
echo "   - Vless WS TLS             : 443" | tee -a log-install.txt
echo "   - Trojan WS TLS            : 443" | tee -a log-install.txt
echo "   - Shadowsocks WS TLS       : 443" | tee -a log-install.txt
echo "   - Vmess WS none TLS        : 80" | tee -a log-install.txt
echo "   - Vless WS none TLS        : 80" | tee -a log-install.txt
echo "   - Trojan WS none TLS       : 80" | tee -a log-install.txt
echo "   - Shadowsocks WS none TLS  : 80" | tee -a log-install.txt
echo "   - Vmess gRPC               : 443" | tee -a log-install.txt
echo "   - Vless gRPC               : 443" | tee -a log-install.txt
echo "   - Trojan gRPC              : 443" | tee -a log-install.txt
echo "   - Shadowsocks gRPC         : 443" | tee -a log-install.txt
echo ""
echo "==================================================================" | tee -a log-install.txt
echo "-----------------------------------------------t.me/givpn_grup----------------------------------------------------" | tee -a log-install.txt
echo "==================================================================" | tee -a log-install.txt
echo -e ""
echo ""
echo "" | tee -a log-install.txt
clear
rm -rf openvpn.sh
sleep 5
cd
clear

