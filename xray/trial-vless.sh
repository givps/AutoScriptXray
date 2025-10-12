#!/bin/bash
# ==========================================
# Create Trial VLess Account
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
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vless WS TLS" | cut -d: -f2 | sed 's/ //g')"
none="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vless WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VLess ports in log file."
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
if ! sed -i '/#vless$/a\#& '"$user $exp"'\
},{"id": "'"$uuid"'","email": "'"$user"'"' /usr/local/etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for VLess WS"
    exit 1
fi

# Add user to config.json for gRPC
if ! sed -i '/#vlessgrpc$/a\#& '"$user $exp"'\
},{"id": "'"$uuid"'","email": "'"$user"'"' /usr/local/etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for VLess gRPC"
    # Restore backup on error
    cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
    exit 1
fi

# Create VLess links dengan parameter yang benar
vlesslink1="vless://${uuid}@bug.com:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}"
vlesslink2="vless://${uuid}@bug.com:${none}?path=%2Fvless&security=none&encryption=none&type=ws&host=${domain}#${user}"
vlesslink3="vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=bug.com#${user}"

# Restart Xray service
if systemctl restart xray > /dev/null 2>&1; then
    # Create client config file
    CLIENT_DIR="/home/vps/public_html"
    mkdir -p "$CLIENT_DIR"
    
    cat > "$CLIENT_DIR/vless-$user.txt" <<-END
# ==========================================
# VLess Trial Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp (1 day trial)
# ==========================================

# VLess WS TLS
${vlesslink1}

# VLess WS None TLS  
${vlesslink2}

# VLess gRPC
${vlesslink3}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $none
- UUID: $uuid
- Encryption: none
- Path WS: /vless
- Service Name gRPC: vless-grpc
- Expiry: $exp (1 day trial)

# For V2RayN / V2RayNG:
- Address: bug.com (TLS) / bug.com (None TLS)
- Port: $tls (TLS) / $none (None TLS)
- UUID: $uuid
- Encryption: none
- Transport: WebSocket (WS) / gRPC
- Path: /vless
- Host: $domain

END

    # Display results
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           TRIAL VLESS           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "Remarks        : ${user} ${yellow}(TRIAL)${nc}"
    echo -e "IP             : ${MYIP}"
    echo -e "Domain         : ${domain}"
    echo -e "Wildcard       : bug.com.${domain}"
    echo -e "Port TLS       : ${tls}"
    echo -e "Port none TLS  : ${none}"
    echo -e "Port gRPC      : ${tls}"
    echo -e "Password       : ${uuid}"
    echo -e "Encryption     : none"
    echo -e "Network        : ws/grpc"
    echo -e "Path WS        : /vless"
    echo -e "ServiceName    : vless-grpc"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link TLS (WS)${nc}"
    echo -e "${vlesslink1}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link none TLS (WS)${nc}"
    echo -e "${vlesslink2}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link gRPC${nc}"
    echo -e "${vlesslink3}"
    echo -e "${red}=========================================${nc}"
    echo -e "Expired On     : $exp ${yellow}(1 day trial)${nc}"
    echo -e "Config File    : $CLIENT_DIR/vless-$user.txt"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Log the creation
    echo "$(date): Created trial VLess account $user (exp: $exp)" >> /var/log/trial-vless.log
    
    echo -e "${green}SUCCESS${nc}: Trial VLess account created!"
    echo -e "${yellow}NOTE${nc}: This is a 1-day trial account"
else
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    echo -e "${yellow}Restoring backup config...${nc}"
    cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
    systemctl restart xray > /dev/null 2>&1
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless
