#!/bin/bash
# =========================================
# setup
# =========================================
set -euo pipefail

# color
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# delete old
rm -f cf.sh >/dev/null 2>&1
rm -f ssh-vpn.sh >/dev/null 2>&1
rm -f ins-xray.sh >/dev/null 2>&1
rm -f insshws.sh >/dev/null 2>&1

# cek root
if [ "${EUID}" -ne 0 ]; then
		echo "${yellow}You need to run this script as root${nc}"
    sleep 5
		exit 1
fi

# set time zone
ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
apt install -y ntp
systemctl enable --now ntp

# disable ipv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

# create folder
mkdir -p /usr/local/etc/xray
mkdir -p /etc/log

echo ""
echo -e "${red}=========================================${nc}"
echo -e "${blue}           SETUP DOMAIN VPS               $NC"
echo -e "${red}=========================================${nc}"
echo -e "${white} 1 = Use Domain Random $NC"
echo -e "${white} 2 = Choose Your Own Domain $NC"
echo -e "${red}=========================================${nc}"
read -rp " input 1 or 2 / pilih 1 atau 2 : " dns
if test $dns -eq 1; then
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cf.sh && chmod +x cf.sh && ./cf.sh
elif test $dns -eq 2; then
read -rp "Enter Your Domain : " dom
echo "$dom" | tee /usr/local/etc/xray/domain /root/domain >/dev/null
else 
echo "Wrong input"
exit 1
fi
echo -e "${green}Done${nc}"

echo -e "${red}=========================================${nc}"
echo -e "${blue}       Install SSH VPN           $NC"
echo -e "${red}=========================================${nc}"
#install ssh vpn
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/ssh-vpn.sh && chmod +x ssh-vpn.sh && ./ssh-vpn.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}          Install XRAY              $NC"
echo -e "${red}=========================================${nc}"
#Instal Xray
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/ins-xray.sh && chmod +x ins-xray.sh && ./ins-xray.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}      Install SSH Websocket           $NC"
echo -e "${red}=========================================${nc}"
# install sshws
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/insshws.sh && chmod +x insshws.sh && ./insshws.sh

cat > /root/.profile << END
# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

mesg n || true
clear
menu
END

systemctl reload-daemon

echo ""
echo -e "${red}=========================================${nc}"  | tee -a log-install.txt
echo -e "${blue}          Service Information            ${nc}"  | tee -a log-install.txt
echo -e "${red}=========================================${nc}"  | tee -a log-install.txt
echo ""
echo "   >>> Service & Port"  | tee -a log-install.txt
echo "   - OpenSSH                  : 22"  | tee -a log-install.txt
echo "   - Dropbear                 : 110" | tee -a log-install.txt
echo "   - SSH Websocket            : 80, 333, 337" | tee -a log-install.txt
echo "   - SSH SSL Websocket        : 443, 444, 447" | tee -a log-install.txt
echo "   - Stunnel4                 : 222, 777," | tee -a log-install.txt
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
echo -e "${red}=========================================${nc}" | tee -a log-install.txt
echo -e "${blue}              t.me/givps_com             ${nc}"  | tee -a log-install.txt
echo -e "${red}=========================================${nc}" | tee -a log-install.txt
echo ""
echo -e "${yellow} Auto reboot in 10 second...${nc}"
sleep 10
reboot

