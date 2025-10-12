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

# System detection
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "IP_NOT_FOUND")
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null || echo "no-domain.com")

# Service ports extraction - CONSISTENT
get_port() {
    local service=$1
    cat /root/log-install.txt 2>/dev/null | grep -w "$service" | cut -f2 -d: | awk '{print $1}'
}

get_ports() {
    local service=$1
    cat /root/log-install.txt 2>/dev/null | grep -w "$service" | cut -f2 -d: | awk '{print $1,$2}'
}

openssh=$(get_port "OpenSSH")
db=$(get_ports "Dropbear")
sshws=$(get_port "SSH Websocket")
sshwssl=$(get_port "SSH SSL Websocket")
ssl=$(get_ports "Stunnel4")

# Generate credentials
Login="trial$(</dev/urandom tr -dc A-Z0-9 | head -c5)"
Pass="pass$(</dev/urandom tr -dc A-Za-z0-9 | head -c8)"
day="1"

echo "Creating trial account..."
echo "Username: $Login"
echo "Password: $Pass"
echo "Expiry: $day day"

# Create user
if useradd -e $(date -d "+$day day" +"%Y-%m-%d") -s /bin/false -M $Login 2>/dev/null; then
    exp=$(chage -l $Login 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
    echo "$Login:$Pass" | passwd 2>/dev/null
    
    clear
    
    # Display information
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}            TRIAL SSH ACCOUNT          ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "Username   : $Login"
    echo -e "Password   : $Pass"
    echo -e "Expired On : $exp"
    echo -e "${red}=========================================${nc}"
    echo -e "IP         : $MYIP"
    echo -e "Host       : $domain"
    echo -e "OpenSSH    : $openssh"
    echo -e "Dropbear   : $db"
    echo -e "SSH WS     : $sshws"
    echo -e "SSH SSL WS : $sshwssl"
    echo -e "SSL/TLS    : $ssl"
    echo -e "UDPGW      : 7100-7900"
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         WebSocket Payloads${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "WSS: GET wss://${domain}/ HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${red}=========================================${nc}"
    echo -e "WS: GET / HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${red}=========================================${nc}"
    
else
    echo -e "${red}ERROR: Failed to create user $Login${nc}"
    exit 1
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
