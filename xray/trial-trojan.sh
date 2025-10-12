#!/bin/bash
# ==========================================
# Create Trial Trojan Account
# ==========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

# Getting system info
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

clear

# Validate domain exists
if [[ -z "$domain" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan WS TLS" | cut -d: -f2 | sed 's/ //g')"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Trojan ports in log file."
    exit 1
fi

# Generate trial user
user="trial$(</dev/urandom tr -dc A-Z0-9 | head -c4)"
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=1
exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# Backup config before modification
cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Add user to config.json for WS
if ! sed -i '/#trojanws$/a\#! '"$user $exp"'\
},{"password": "'"$uuid"'","email": "'"$user"'"' /usr/local/etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for Trojan WS"
    exit 1
fi

# Add user to config.json for gRPC
if ! sed -i '/#trojangrpc$/a\#! '"$user $exp"'\
},{"password": "'"$uuid"'","email": "'"$user"'"' /usr/local/etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for Trojan gRPC"
    # Restore backup on error
    cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
    exit 1
fi

# Create Trojan links dengan path yang benar
trojanlink1="trojan://${uuid}@${domain}:${tls}?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni=bug.com#${user}"
trojanlink="trojan://${uuid}@bug.com:${tls}?path=%2Ftrojan&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
trojanlink2="trojan://${uuid}@bug.com:${ntls}?path=%2Ftrojan&security=none&host=${domain}&type=ws#${user}"

# Restart Xray service
if systemctl restart xray > /dev/null 2>&1; then
    # Create client config file
    CLIENT_DIR="/home/vps/public_html"
    mkdir -p "$CLIENT_DIR"
    
    cat > "$CLIENT_DIR/trojan-$user.txt" <<-END
# ==========================================
# Trojan Trial Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp (1 day trial)
# ==========================================

# Trojan WS TLS
${trojanlink}

# Trojan WS None TLS  
${trojanlink2}

# Trojan gRPC
${trojanlink1}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $ntls
- Password: $uuid
- Path: /trojan
- Service Name: trojan-grpc
- Expiry: $exp (1 day trial)

# For V2RayN / V2RayNG:
- Address: bug.com (TLS) / bug.com (None TLS)
- Port: $tls (TLS) / $ntls (None TLS)
- Password: $uuid
- Transport: WebSocket (WS) / gRPC
- Path: /trojan
- Host: $domain

END

    # Display results
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           TRIAL TROJAN           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "Remarks        : ${user} ${yellow}(TRIAL)${nc}"
    echo -e "IP             : ${MYIP}"
    echo -e "Domain         : ${domain}"
    echo -e "Wildcard       : bug.com.${domain}"
    echo -e "Port TLS       : ${tls}"
    echo -e "Port none TLS  : ${ntls}"
    echo -e "Port gRPC      : ${tls}"
    echo -e "Password       : ${uuid}"
    echo -e "Network        : ws/grpc"
    echo -e "Path WS        : /trojan"
    echo -e "ServiceName    : trojan-grpc"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link TLS (WS)${nc}"
    echo -e "${trojanlink}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link none TLS (WS)${nc}"
    echo -e "${trojanlink2}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link gRPC${nc}"
    echo -e "${trojanlink1}"
    echo -e "${red}=========================================${nc}"
    echo -e "Expired On     : $exp ${yellow}(1 day trial)${nc}"
    echo -e "Config File    : $CLIENT_DIR/trojan-$user.txt"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Log the creation
    echo "$(date): Created trial Trojan account $user (exp: $exp)" >> /var/log/trial-trojan.log
    
    echo -e "${green}SUCCESS${nc}: Trial Trojan account created!"
    echo -e "${yellow}NOTE${nc}: This is a 1-day trial account"
else
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    echo -e "${yellow}Restoring backup config...${nc}"
    cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
    systemctl restart xray > /dev/null 2>&1
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-trojan
