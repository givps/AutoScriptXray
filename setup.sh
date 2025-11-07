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
rm -f ssh-vpn.sh >/dev/null 2>&1
rm -f ins-xray.sh >/dev/null 2>&1
rm -f udp-custom.sh >/dev/null 2>&1
rm -f slowdns.sh >/dev/null 2>&1

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Script need run AS root...!"
    exit 1
fi

# Detect OS
if [ -f /etc/debian_version ]; then
    OS="debian"
elif [ -f /etc/lsb-release ]; then
    OS="ubuntu"
else
    print_error "OS Not Support. Script for OS Debian/Ubuntu."
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

# create folder
mkdir -p /usr/local/etc/xray
mkdir -p /etc/log

MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
clear
echo -e "${red}=========================================${nc}"
echo -e "${green}     CUSTOM SETUP DOMAIN VPS     ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Use Domain From Script"
echo -e "${white}2${nc} Choose Your Own Domain"
echo -e "${red}=========================================${nc}"
read -rp "Choose Your Domain Installation 1/2 : " dom 

if [[ $dom -eq 1 ]]; then
    clear
    rm -f /root/cf.sh
    wget -q -O /root/cf.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cf.sh"
    chmod +x /root/cf.sh && bash /root/cf.sh

elif [[ $dom -eq 2 ]]; then
    read -rp "Enter Your Domain : " domen
    rm -f /usr/local/etc/xray/domain /root/domain
    echo "$domen" | tee /usr/local/etc/xray/domain /root/domain >/dev/null

    echo -e "\n${yellow}Checking DNS record for ${domen}...${nc}"
    DNS_IP=$(dig +short A "$domen" @1.1.1.1 | head -n1)

    if [[ -z "$DNS_IP" ]]; then
        echo -e "${red}No DNS record found for ${domen}.${nc}"
    elif [[ "$DNS_IP" != "$MYIP" ]]; then
        echo -e "${yellow}⚠ Domain does not point to this VPS.${nc}"
        echo -e "Your VPS IP: ${green}$MYIP${nc}"
        echo -e "Current DNS IP: ${red}$DNS_IP${nc}"
    else
        echo -e "${green}✅ Domain already points to this VPS.${nc}"
    fi

    # If not pointing, offer Cloudflare API creation
    if [[ "$DNS_IP" != "$MYIP" ]]; then
        echo -e "\n${yellow}Would you like to create an A record on Cloudflare using API Token?${nc}"
        read -rp "Create record automatically? (y/n): " ans
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
            read -rp "Enter your Cloudflare API Token: " CF_API
            read -rp "Enter your Cloudflare Zone Name / Primary Domain Name (e.g. example.com): " CF_ZONE
            ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_ZONE}" \
                -H "Authorization: Bearer ${CF_API}" \
                -H "Content-Type: application/json" | jq -r '.result[0].id')

            if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
                echo -e "${red}Failed to get Zone ID. Please check your token and zone name.${nc}"
            else
                echo -e "${green}Zone ID found: ${ZONE_ID}${nc}"
                # Create or update DNS record
                RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${domen}" \
                    -H "Authorization: Bearer ${CF_API}" \
                    -H "Content-Type: application/json" | jq -r '.result[0].id')

                if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
                    echo -e "${yellow}Creating new A record for ${domen}...${nc}"
                    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
                        -H "Authorization: Bearer ${CF_API}" \
                        -H "Content-Type: application/json" \
                        --data "{\"type\":\"A\",\"name\":\"${domen}\",\"content\":\"${MYIP}\",\"ttl\":120,\"proxied\":false}" >/dev/null
                else
                    echo -e "${yellow}Updating existing A record for ${domen}...${nc}"
                    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
                        -H "Authorization: Bearer ${CF_API}" \
                        -H "Content-Type: application/json" \
                        --data "{\"type\":\"A\",\"name\":\"${domen}\",\"content\":\"${MYIP}\",\"ttl\":120,\"proxied\":false}" >/dev/null
                fi
                echo -e "${green}✅ DNS record set to ${MYIP}${nc}"
            fi
        fi
    fi
else 
    echo -e "${red}Wrong Argument${nc}"
    exit 1
fi
echo -e "${green}Done${nc}"

echo -e "${red}=========================================${nc}"
echo -e "${blue}       Install SSH VPN           ${nc}"
echo -e "${red}=========================================${nc}"
#install ssh vpn
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/ssh-vpn.sh && chmod +x ssh-vpn.sh && ./ssh-vpn.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}          Install XRAY              ${nc}"
echo -e "${red}=========================================${nc}"
#Instal Xray
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/ins-xray.sh && chmod +x ins-xray.sh && ./ins-xray.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}      Install SSH Websocket           ${nc}"
echo -e "${red}=========================================${nc}"
# install sshws
# wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws/install-ws.sh && chmod +x install-ws.sh && ./install-ws.sh

# ==========================================
# INSTALL WEBSOCKET PROXY.JS
# ==========================================
LOG_FILE="/var/log/ws-proxy-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "Starting WebSocket Proxy.js installation..."
echo "========================================="

# -------------------------------
# Set non-interactive mode
# -------------------------------
export DEBIAN_FRONTEND=noninteractive

# -------------------------------
# Update & Install dependencies
# -------------------------------
echo "[STEP 1] Updating system and installing packages..."
apt update -y || true
apt upgrade -y || true
apt install -y wget curl lsof net-tools ufw build-essential || true
# -------------------------------
# Install Node.js
# -------------------------------
echo "[STEP 2] Checking Node.js version..."
apt remove -y nodejs npm || true
NODE_VERSION=$(node -v 2>/dev/null || echo "v0")
NODE_MAJOR=${NODE_VERSION#v}
NODE_MAJOR=${NODE_MAJOR%%.*}

if [[ $NODE_MAJOR -lt 16 ]]; then
    echo "Node.js version too old ($NODE_VERSION). Installing Node.js 18..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - || true
    apt install -y nodejs || true
else
    echo "Node.js version is sufficient ($NODE_VERSION)"
fi

# -------------------------------
# Download proxy.js
# -------------------------------
echo "[STEP 3] Downloading proxy.js..."
rm -f /usr/local/bin/proxy.js
wget -q -O /usr/local/bin/proxy.js https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws-stunnel/proxy.js
chmod +x /usr/local/bin/proxy.js
echo "[STEP 3] proxy.js installed at /usr/local/bin/proxy.js"

# -------------------------------
# Download systemd service
# -------------------------------
echo "[STEP 4] Setting up ws-proxy systemd service..."
rm -f /etc/systemd/system/ws-proxy.service
wget -q -O /etc/systemd/system/ws-proxy.service https://raw.githubusercontent.com/givps/AutoScriptXray/master/ws-stunnel/ws-proxy.service
chmod 644 /etc/systemd/system/ws-proxy.service

cd /usr/local/bin
npm install ws
npm init -y

# Reload systemd to recognize new service
systemctl daemon-reload || true

# Enable and start ws-proxy service
systemctl enable ws-proxy || true
systemctl restart ws-proxy || true

# -------------------------------
# Verify service
# -------------------------------
if systemctl is-active --quiet ws-proxy; then
    echo "[STEP 5] ws-proxy service is active and running."
else
    echo "[WARNING] ws-proxy service failed to start. Check logs with: journalctl -u ws-proxy -f"
fi

# -------------------------------
# Final message
# -------------------------------
echo "========================================="
echo "WebSocket Proxy.js installation complete!"
echo "You can check the service status: systemctl status ws-proxy"
echo "========================================="

#echo -e "${red}=========================================${nc}"
#echo -e "${blue}             Install SlowDNS            ${nc}"
#echo -e "${red}=========================================${nc}"
# install slowdns
# wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/slowdns/slowdns.sh && chmod +x slowdns.sh && ./slowdns.sh

#echo -e "${red}=========================================${nc}"
#echo -e "${blue}               Install Tor              ${nc}"
#echo -e "${red}=========================================${nc}"
# install tor
#wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/tor.sh && chmod +x tor.sh && ./tor.sh

#echo -e "${red}=========================================${nc}"
#echo -e "${blue}           Install UDP CUSTOM           ${nc}"
#echo -e "${red}=========================================${nc}"
# install udp-custom
# wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/udp-custom.sh && chmod +x udp-custom.sh && ./udp-custom.sh

echo -e "${red}=========================================${nc}"
echo -e "${blue}           Install OpenVPN              ${nc}"
echo -e "${red}=========================================${nc}"
# install tor openvpn
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/openvpn.sh && chmod +x openvpn.sh && ./openvpn.sh

cat > /root/.profile <<'EOF'
# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

mesg n || true
clear
command -v menu >/dev/null 2>&1 && menu
EOF

apt install -y netfilter-persistent iptables-persistent
# Flush
iptables -L INPUT -n --line-numbers
# Allow loopback
iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || \
iptables -I INPUT -i lo -j ACCEPT
# Allow established connections
iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Allow SSH & Dropbear
iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -C INPUT -p tcp --dport 2222 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 2222 -j ACCEPT
iptables -C INPUT -p tcp --dport 109 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 109 -j ACCEPT
iptables -C INPUT -p tcp --dport 110 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 110 -j ACCEPT
iptables -C INPUT -p tcp --dport 222 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 222 -j ACCEPT
iptables -C INPUT -p tcp --dport 333 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 333 -j ACCEPT
iptables -C INPUT -p tcp --dport 444 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 444 -j ACCEPT
iptables -C INPUT -p tcp --dport 777 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 777 -j ACCEPT
iptables -C INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
# Allow HTTP/HTTPS
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
# Allow HTTP/HTTPS nginx
iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
iptables -C INPUT -p tcp --dport 4433 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 4433 -j ACCEPT
# Allow WebSocket ports
iptables -C INPUT -p tcp --dport 1444 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1444 -j ACCEPT
iptables -C INPUT -p tcp --dport 1445 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1445 -j ACCEPT
# Save
netfilter-persistent save
# chattr +i /etc/iptables/rules.v4
netfilter-persistent reload

systemctl enable netfilter-persistent
systemctl start netfilter-persistent

echo ""
echo -e "========================================="  | tee -a ~/log-install.txt
echo -e "          Service Information            "  | tee -a ~/log-install.txt
echo -e "========================================="  | tee -a ~/log-install.txt
echo ""
echo "   >>> Service & Port"  | tee -a ~/log-install.txt
echo "   - OpenSSH                  : 22, 2222"  | tee -a ~/log-install.txt
echo "   - Dropbear                 : 109, 110" | tee -a ~/log-install.txt
echo "   - SSH Websocket            : 80, 1445" | tee -a ~/log-install.txt
echo "   - SSH SSL Websocket        : 444, 1444" | tee -a ~/log-install.txt
echo "   - Stunnel4                 : 222, 333, 777" | tee -a ~/log-install.txt
echo "   - Badvpn                   : 7100-7900" | tee -a ~/log-install.txt
echo "   - OpenVPN                  : 443, 1195, 51825" | tee -a ~/log-install.txt
echo "   - Nginx                    : 80" | tee -a ~/log-install.txt
echo "   - Vmess WS TLS             : 443" | tee -a ~/log-install.txt
echo "   - Vless WS TLS             : 443" | tee -a ~/log-install.txt
echo "   - Trojan WS TLS            : 443" | tee -a ~/log-install.txt
echo "   - Shadowsocks WS TLS       : 443" | tee -a ~/log-install.txt
echo "   - Vmess WS none TLS        : 80" | tee -a ~/log-install.txt
echo "   - Vless WS none TLS        : 80" | tee -a ~/log-install.txt
echo "   - Trojan WS none TLS       : 80" | tee -a ~/log-install.txt
echo "   - Shadowsocks WS none TLS  : 80" | tee -a ~/log-install.txt
echo "   - Vmess gRPC               : 443" | tee -a ~/log-install.txt
echo "   - Vless gRPC               : 443" | tee -a ~/log-install.txt
echo "   - Trojan gRPC              : 443" | tee -a ~/log-install.txt
echo "   - Shadowsocks gRPC         : 443" | tee -a ~/log-install.txt
echo ""
echo -e "=========================================" | tee -a ~/log-install.txt
echo -e "               t.me/givps_com            "  | tee -a ~/log-install.txt
echo -e "=========================================" | tee -a ~/log-install.txt
echo ""
echo -e "Auto reboot in 10 seconds..."
sleep 10
clear
reboot
