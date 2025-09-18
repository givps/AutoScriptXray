#!/bin/bash
# color variables
BGreen='\e[1;32m'
NC='\e[0m'

# Get VPS Public IP
MYIP=$(wget -qO- ipv4.icanhazip.com);
DOMAIN=""
if [ -f "/etc/xray/domain" ]; then
DOMAIN=$(cat /etc/xray/domain)
echo "$DOMAIN" > /root/domain
fi

# Detect squid package name
PKG="squid"
COREDIR="/var/spool/squid"
if apt-cache show squid3 >/dev/null 2>&1; then
    PKG="squid3"
    COREDIR="/var/spool/squid3"
fi

echo "[INFO] Installing package: $PKG"
apt update -y
apt install -y $PKG

# Backup default config
if [ -f "/etc/$PKG/squid.conf" ]; then
    mv /etc/$PKG/squid.conf /etc/$PKG/squid.conf.bak
fi

# Create new config
cat > /etc/$PKG/squid.conf <<-END
# =============================
# Squid Proxy Configuration
# AutoScriptXray Edition
# =============================

acl manager proto cache_object
acl localhost src 127.0.0.1/32 ::1
acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1

# Allowed Ports
acl SSL_ports port 443
acl SSL_ports port 442
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777

# Methods
acl CONNECT method CONNECT

# Allow SSH Tunnel via IP
acl SSH dst ${MYIP}

# Allow SSH Tunnel via domain (if available)
END

if [ -n "$DOMAIN" ]; then
cat >> /etc/$PKG/squid.conf <<-END
acl SSHDOMAIN dst_domain ${DOMAIN}
http_access allow SSHDOMAIN
END
fi

cat >> /etc/$PKG/squid.conf <<-END

# Access rules
http_access allow SSH
http_access allow manager localhost
http_access deny manager
http_access allow localhost
http_access deny all

# Ports
http_port 8000
http_port 3128

# Cache / Storage
coredump_dir $COREDIR

refresh_pattern ^ftp:        1440    20%    10080
refresh_pattern ^gopher:     1440     0%     1440
refresh_pattern -i (/cgi-bin/|\?) 0  0%        0
refresh_pattern .            0       20%     4320

# Hostname
visible_hostname givps-proxy
END

# Init cache dir
mkdir -p $COREDIR
squid -z -f /etc/$PKG/squid.conf

# Restart service
systemctl restart $PKG
systemctl enable $PKG

echo "===================================="
echo " Squid Proxy Installed Successfully "
echo "------------------------------------"
echo " VPS IP     : $MYIP"
if [ -n "$DOMAIN" ]; then
echo " Domain     : $DOMAIN"
fi
echo " Port       : 3128, 8000"
echo " Package    : $PKG"
echo " Config     : /etc/$PKG/squid.conf"
echo " Status     : systemctl status $PKG"
echo "===================================="
sleep 5

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
