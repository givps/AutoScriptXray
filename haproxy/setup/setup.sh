#!/bin/bash
# =========================================
# setup
# =========================================

# color
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# delete old
rm -f cf.sh >/dev/null 2>&1
rm -f tool.sh >/dev/null 2>&1
rm -f ins-xray.sh >/dev/null 2>&1
rm -f install-haproxy.sh >/dev/null 2>&1

# cek root
if [ "${EUID}" -ne 0 ]; then
		echo "${yellow}You need to run this script as root${nc}"
    sleep 5
		exit 1
fi

# -------------------------------
# 1️⃣ Set timezone ke Asia/Jakarta
# -------------------------------
echo "Setting timezone to Asia/Jakarta..."
timedatectl set-timezone Asia/Jakarta
echo "Timezone set:"
timedatectl | grep "Time zone"

# -------------------------------
# 2️⃣ Enable NTP (auto-sync waktu)
# -------------------------------
echo "Enabling NTP..."
timedatectl set-ntp true

# Cek status sinkronisasi
timedatectl status | grep -E "NTP enabled|NTP synchronized"

# -------------------------------
# 3️⃣ Install & enable cron
# -------------------------------
if ! systemctl list-unit-files | grep -q '^cron.service'; then
    echo "Cron not found. Installing cron..."
    apt update -y
    apt install -y cron
fi

echo "Enabling and starting cron service..."
systemctl enable cron
systemctl restart cron

echo ""
echo "✅ VPS timezone, NTP, and cron setup complete!"

# disable ipv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1

# create folder
mkdir -p /usr/local/etc/xray
mkdir -p /etc/log

echo ""
echo -e "${red}=========================================${nc}"
echo -e "${blue}           SETUP DOMAIN VPS               ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white} 1 = Use Domain Random ${nc}"
echo -e "${white} 2 = Choose Your Own Domain ${nc}"
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
echo -e "${blue}              Install Tool              ${nc}"
echo -e "${red}=========================================${nc}"
#install tool
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/setup/tool.sh && chmod +x tool.sh && ./tool.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}              Install XRAY              ${nc}"
echo -e "${red}=========================================${nc}"
#Instal Xray
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/ins-xray.sh && chmod +x ins-xray.sh && ./ins-xray.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}     Install SSH HAProxy Websocket      ${nc}"
echo -e "${red}=========================================${nc}"
# install haproxy ws
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/setup/install-haproxy.sh && chmod +x install-haproxy.sh && ./install-haproxy.sh

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
echo "   - OpenSSH                  : 22, 2222"  | tee -a log-install.txt
echo "   - SSH Direct SSL           : 1445"  | tee -a log-install.txt
echo "   - SSH Direct               : 1446"  | tee -a log-install.txt
echo "   - HAProxy SSH SSL WS       : 443, 1443" | tee -a log-install.txt
echo "   - HAProxy SSH WS           : 80, 1444" | tee -a log-install.txt
echo "   - Badvpn                   : 7100-7900" | tee -a log-install.txt
echo "   - Nginx                    : 80" | tee -a log-install.txt
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

