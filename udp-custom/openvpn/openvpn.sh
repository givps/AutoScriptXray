#!/bin/bash
# color variables
BGreen='\e[1;32m'
NC='\e[0m'

# get domain
domain=$(cat /etc/xray/domain)
echo "$domain" > /root/domain
clear

MYIP=$(wget -qO- ipv4.icanhazip.com);
MYIP2="s/xxxxxxxxx/$MYIP/g";

# =========================================
# install squid
echo -e "\e[1;32m Installing Squid Proxy.. \e[0m"
apt -y install squid
wget -O /etc/squid/squid.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/openvpn/squid3.conf"
sed -i $MYIP2 /etc/squid/squid.conf

# =========================================
# install openvpn
echo -e "\e[1;32m OpenVPN Installation Process.. \e[0m"
wget -O vpn.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/openvpn/vpn.sh"
chmod +x vpn.sh && ./vpn.sh

# =========================================
# set ownership for web dir
cd
chown -R www-data:www-data /home/vps/public_html

# =========================================
# restart all essential services
echo -e "$BGreen[SERVICE]$NC Restarting SSH, OpenVPN and related services"
sleep 0.5
systemctl restart nginx >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted nginx"
systemctl restart openvpn@server >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted openvpn"
systemctl restart cron >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted cron"
systemctl restart ssh >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted ssh"
systemctl restart dropbear >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted dropbear"
systemctl restart fail2ban >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted fail2ban"
systemctl restart stunnel4 >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted stunnel4"
systemctl restart vnstat >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted vnstat"
systemctl restart squid >/dev/null 2>&1 && echo -e "[ ${BGreen}ok${NC} ] Restarted squid"

# =========================================
# service info
clear
echo "=================================================================="  | tee -a log-install.txt
echo "----------------------------------------- Service Information ---------------------------------------------"  | tee -a log-install.txt
echo "=================================================================="  | tee -a log-install.txt
echo ""
echo "   >>> Services & Ports"  | tee -a log-install.txt
echo "   - OpenSSH                  : 22/110"  | tee -a log-install.txt
echo "   - OpenVPN TCP              : 1194"  | tee -a log-install.txt
echo "   - OpenVPN UDP              : 2200"  | tee -a log-install.txt
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
echo "-------------------------------------------- t.me/givpn_grup ----------------------------------------------" | tee -a log-install.txt
echo "==================================================================" | tee -a log-install.txt
echo -e ""
echo "" | tee -a log-install.txt

# =========================================
# cleanup
rm -f vpn.sh
sleep 3
clear
