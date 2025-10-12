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

# Get service ports dengan error handling
get_service_port() {
    local service=$1
    local port=$(cat /root/log-install.txt 2>/dev/null | grep -w "$service" | cut -f2 -d: | awk '{$1=$1};1')
    echo "${port:-Not Found}"
}

openssh=$(get_service_port "OpenSSH")
db=$(get_service_port "Dropbear") 
sshws=$(get_service_port "SSH Websocket")
sshwssl=$(get_service_port "SSH SSL Websocket")
ssl=$(get_service_port "Stunnel4")

# Create user
useradd -e $(date -d "$day day" +"%Y-%m-%d") -s /bin/false -M $Login
if [ $? -ne 0 ]; then
    echo -e "${red}Failed to create user!${nc}"
    exit 1
fi

exp="$(chage -l $Login | grep "Account expires" | awk -F": " '{print $2}')"
echo -e "$Pass\n$Pass\n" | chpasswd $Login &> /dev/null

if [ $? -ne 0 ]; then
    echo -e "${red}Failed to set password!${nc}"
    userdel $Login 2>/dev/null
    exit 1
fi

# Log file
log_file="/var/log/create-ssh.log"

# Display account info
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
echo -e "OpenSSH     : $openssh"
echo -e "Dropbear    : $db"
echo -e "SSH WS      : $sshws"
echo -e "SSH SSL WS  : $sshwssl"
echo -e "SSL/TLS     : $ssl"
echo -e "UDPGW       : 7100-7900"
echo -e "${red}=========================================${nc}"
} | tee -a "$log_file"

# Add WebSocket payloads if domain exists
if [ -n "$domain" ]; then
    {
    echo -e "${blue}         WebSocket Payloads${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "GET wss://${domain}/ HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${red}=========================================${nc}"
    echo -e "Payload WS" 
    echo -e "GET / HTTP/1.1[crlf]Host: $domain[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${red}=========================================${nc}"
    } | tee -a "$log_file"
fi

echo -e "${green}User $Login created successfully!${nc}"
echo -e "${yellow}Details saved to $log_file${nc}"
echo ""

read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
