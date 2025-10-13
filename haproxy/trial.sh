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

# System detection
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "IP_NOT_FOUND")
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null || echo "no-domain.com")

# Service ports untuk HAProxy WebSocket - CONSISTENT
get_port() {
    local service=$1
    cat /root/log-install.txt 2>/dev/null | grep -w "$service" | cut -f2 -d: | awk '{print $1}'
}

# Default ports untuk HAProxy WebSocket setup
openssh=$(get_service_port "OpenSSH" || echo "22")
haproxy_ssl=$(get_service_port "HAProxy SSH SSL WS" || echo "1443")
haproxy_non_ssl=$(get_service_port "HAProxy SSH WS" || echo "1444")
ssh_direct_ssl=$(get_service_port "SSH Direct SSL" || echo "1445")
ssh_direct_non_ssl=$(get_service_port "SSH Direct" || echo "1446")

# Generate credentials
Login="trial$(</dev/urandom tr -dc A-Z0-9 | head -c5)"
Pass="pass$(</dev/urandom tr -dc A-Za-z0-9 | head -c8)"
day="1"

echo "Creating trial account..."
echo "Username: $Login"
echo "Password: $Pass"
echo "Expiry: $day day"

# Create user
if useradd -e $(date -d "+$day days" +"%Y-%m-%d") -s /bin/false -M $Login 2>/dev/null; then
    exp=$(chage -l $Login 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
    echo "$Login:$Pass" | chpasswd 2>/dev/null
    
    # Sync password dan restart services
    pwconv 2>/dev/null
    systemctl restart ssh haproxy ws-proxy 2>/dev/null
    
    sleep 2
    
    clear
    
    # Display information - UPDATED untuk HAProxy WebSocket
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}            TRIAL SSH ACCOUNT          ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "Username   : $Login"
    echo -e "Password   : $Pass"
    echo -e "Expired On : $exp"
    echo -e "${red}=========================================${nc}"
    echo -e "IP         : $MYIP"
    echo -e "Host       : $domain"
    echo -e "${blue}🔧 HAProxy WebSocket:${nc}"
    echo -e "SSL WS     : $haproxy_ssl"
    echo -e "Non-SSL WS : $haproxy_non_ssl"
    echo -e "${blue}🔌 Direct SSH:${nc}"
    echo -e "SSL Direct : $ssh_direct_ssl"
    echo -e "Non-SSL    : $ssh_direct_non_ssl"
    echo -e "OpenSSH    : $openssh"
echo -e "UDPGW       : 7100-7900"
    echo -e "${red}=========================================${nc}"
    
    # WebSocket Payloads untuk HAProxy
    echo -e "${blue}         HAProxy WebSocket Payloads${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}SSL WebSocket (Port $haproxy_ssl):${nc}"
    echo -e "CONNECT [host_port] HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e ""
    echo -e "${green}Non-SSL WebSocket (Port $haproxy_non_ssl):${nc}"
    echo -e "CONNECT [host_port] HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${red}=========================================${nc}"
    
    # Quick Connection URLs
    echo -e "${blue}         Quick Connection URLs${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}SSL WebSocket:${nc}"
    echo -e "wss://${domain}:$haproxy_ssl/"
    echo -e ""
    echo -e "${green}Non-SSL WebSocket:${nc}"
    echo -e "ws://${domain}:$haproxy_non_ssl/"
    echo -e "${red}=========================================${nc}"
    
    # Direct SSH Commands
    echo -e "${blue}         Direct SSH Commands${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}SSH Direct SSL:${nc}"
    echo -e "ssh -p $ssh_direct_ssl $Login@${domain}"
    echo -e ""
    echo -e "${green}SSH Direct Non-SSL:${nc}"
    echo -e "ssh -p $ssh_direct_non_ssl $Login@${domain}"
    echo -e "${red}=========================================${nc}"
    
    # Trial Usage Note
    echo -e "${yellow}💡 Trial Usage Note:${nc}"
    echo -e "This trial account will expire in 1 day"
    echo -e "Use any of the connection methods above"
    echo -e "${red}=========================================${nc}"
    
else
    echo -e "${red}ERROR: Failed to create user $Login${nc}"
    exit 1
fi

# Log trial creation
log_file="/var/log/trial-ssh.log"
{
echo "$(date): Trial user created - Username: $Login, IP: $MYIP, Expiry: $exp"
} >> "$log_file"

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn