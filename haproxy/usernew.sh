#!/bin/bash
# =========================================
# CREATE SSH USER - HAPROXY WEBSOCKET VERSION
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

echo -e "${red}=========================================${nc}"
echo -e "${red}            CREATE SSH USER             ${nc}"
echo -e "${red}=========================================${nc}"

# Input validation
read -p "Username : " Login
if [ -z "$Login" ]; then
    echo -e "${red}Username cannot be empty!${nc}"
    exit 1
fi

# Check if user exists
if id "$Login" &>/dev/null; then
    echo -e "${red}User $Login already exists!${nc}"
    exit 1
fi

read -p "Password : " Pass
if [ -z "$Pass" ]; then
    echo -e "${red}Password cannot be empty!${nc}"
    exit 1
fi

read -p "Expired (day): " day
if ! [[ "$day" =~ ^[0-9]+$ ]] || [ "$day" -lt 1 ]; then
    echo -e "${red}Expired day must be a positive number!${nc}"
    exit 1
fi

# Get service ports untuk HAProxy WebSocket
get_service_port() {
    local service=$1
    local port=$(cat /root/log-install.txt 2>/dev/null | grep -w "$service" | cut -f2 -d: | awk '{$1=$1};1')
    echo "${port:-Not Found}"
}

# Hanya ambil port yang relevan dengan HAProxy WebSocket
openssh=$(get_service_port "OpenSSH" || echo "22")
haproxy_ssl=$(get_service_port "HAProxy SSH SSL WS" || echo "1443")
haproxy_non_ssl=$(get_service_port "HAProxy SSH WS" || echo "1444")
ssh_direct_ssl=$(get_service_port "SSH Direct SSL" || echo "1445")
ssh_direct_non_ssl=$(get_service_port "SSH Direct" || echo "1446")

# Create user
useradd -e $(date -d "$day days" +"%Y-%m-%d") -s /bin/false -M $Login
if [ $? -ne 0 ]; then
    echo -e "${red}Failed to create user!${nc}"
    exit 1
fi

exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"
echo "$Login:$Pass" | chpasswd

if [ $? -ne 0 ]; then
    echo -e "${red}Failed to set password!${nc}"
    userdel $Login 2>/dev/null
    exit 1
fi

# Force password sync dan restart services
pwconv
systemctl restart ssh haproxy ws-proxy

sleep 2

# Test authentication
echo -e "${yellow}Testing user authentication...${nc}"
if echo "$Login:testpass" | chpasswd -e &>/dev/null; then
    echo -e "${green}✓ User authentication test passed${nc}"
else
    if grep -q "^$Login:" /etc/shadow && ! grep -q "^$Login:[*!]" /etc/shadow; then
        echo -e "${green}✓ User exists in shadow file${nc}"
    else
        echo -e "${red}✗ User authentication test failed${nc}"
    fi
fi

# Log file
log_file="/var/log/create-ssh.log"

# Display account info - UPDATED untuk HAProxy WebSocket
{
echo -e "${red}=========================================${nc}"
echo -e "${red}            SSH ACCOUNT CREATED         ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "Username    : $Login"
echo -e "Password    : $Pass" 
echo -e "Expired On  : $exp"
echo -e "${red}=========================================${nc}"
echo -e "IP          : $MYIP"
echo -e "Host        : ${domain:-Not Set}"
echo -e "${blue}🔧 HAProxy WebSocket:${nc}"
echo -e "SSL WS      : $haproxy_ssl"
echo -e "Non-SSL WS  : $haproxy_non_ssl"
echo -e "${blue}🔌 Direct SSH:${nc}"
echo -e "SSL Direct  : $ssh_direct_ssl"
echo -e "Non-SSL     : $ssh_direct_non_ssl"
echo -e "OpenSSH     : $openssh"
echo -e "UDPGW       : 7100-7900"
echo -e "${red}=========================================${nc}"
} | tee -a "$log_file"

# Add WebSocket payloads untuk HAProxy
{
echo -e "${blue}         HAProxy WebSocket Payloads${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}SSL WebSocket (Port $haproxy_ssl):${nc}"
echo -e "CONNECT [host_port] HTTP/1.1[crlf]Host: ${domain:-$MYIP}[crlf]Upgrade: websocket[crlf][crlf]"
echo -e ""
echo -e "${green}Non-SSL WebSocket (Port $haproxy_non_ssl):${nc}"
echo -e "CONNECT [host_port] HTTP/1.1[crlf]Host: ${domain:-$MYIP}[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Example URLs:${nc}"
echo -e "SSL WS    : wss://${domain:-$MYIP}:$haproxy_ssl/"
echo -e "Non-SSL WS: ws://${domain:-$MYIP}:$haproxy_non_ssl/"
echo -e "${red}=========================================${nc}"
} | tee -a "$log_file"

# Test connection info
{
echo -e "${blue}         Connection Test Commands${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}Direct SSH SSL:${nc}"
echo -e "ssh -p $ssh_direct_ssl $Login@${domain:-$MYIP}"
echo -e ""
echo -e "${green}Direct SSH Non-SSL:${nc}"
echo -e "ssh -p $ssh_direct_non_ssl $Login@${domain:-$MYIP}"
echo -e "${red}=========================================${nc}"
} | tee -a "$log_file"

echo -e "${green}User $Login created successfully!${nc}"
echo -e "${yellow}Details saved to $log_file${nc}"

# Display quick connection info
echo -e "\n${blue}🎯 Quick Connection Info:${nc}"
echo -e "SSL WebSocket    : ${yellow}wss://${domain:-$MYIP}:$haproxy_ssl/${nc}"
echo -e "Non-SSL WebSocket: ${yellow}ws://${domain:-$MYIP}:$haproxy_non_ssl/${nc}"
echo -e "Direct SSH SSL   : ${yellow}ssh -p $ssh_direct_ssl $Login@${domain:-$MYIP}${nc}"
echo -e "Direct SSH       : ${yellow}ssh -p $ssh_direct_non_ssl $Login@${domain:-$MYIP}${nc}"

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn