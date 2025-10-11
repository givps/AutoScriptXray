#!/bin/bash
# ==========================================
# Create Trial Shadowsocks Account
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
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS TLS" | cut -d: -f2 | sed 's/ //g')"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Shadowsocks ports in log file."
    exit 1
fi

# Generate trial user
user="trial$(</dev/urandom tr -dc A-Z0-9 | head -c4)"
cipher="aes-128-gcm"
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=1
exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# Backup config before modification
cp /etc/xray/config.json /etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Add user to config.json
if ! sed -i '/#ssws$/a\### '"$user $exp"'\
},{"password": "'"$uuid"'","method": "'"$cipher"'","email": "'"$user"'"' /etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for WS"
    exit 1
fi

if ! sed -i '/#ssgrpc$/a\### '"$user $exp"'\
},{"password": "'"$uuid"'","method": "'"$cipher"'","email": "'"$user"'"' /etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for gRPC"
    # Restore backup on error
    cp /etc/xray/config.json.backup.* /etc/xray/config.json 2>/dev/null
    exit 1
fi

# Create shadowsocks links
echo "$cipher:$uuid" > /tmp/log
shadowsocks_base64=$(cat /tmp/log)
echo -n "${shadowsocks_base64}" | base64 > /tmp/log1
shadowsocks_base64e=$(cat /tmp/log1)

# Fix: Corrected link parameters
shadowsockslink="ss://${shadowsocks_base64e}@bug.com:${tls}?path=%2Fss-ws&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
shadowsockslink2="ss://${shadowsocks_base64e}@bug.com:${ntls}?path=%2Fss-ws&security=none&host=${domain}&type=ws#${user}"
shadowsockslink1="ss://${shadowsocks_base64e}@${domain}:${tls}?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni=bug.com#${user}"

# Restart services
if systemctl restart xray > /dev/null 2>&1; then
    service cron restart > /dev/null 2>&1
    
    # Cleanup temp files
    rm -rf /tmp/log /tmp/log1
    
    # Create client config file
    CLIENT_DIR="/home/vps/public_html"
    mkdir -p "$CLIENT_DIR"
    
    cat > "$CLIENT_DIR/ss-$user.txt" <<-END
# ==========================================
# Shadowsocks Trial Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp (1 day trial)
# ==========================================

# Shadowsocks WS TLS
${shadowsockslink}

# Shadowsocks WS None TLS  
${shadowsockslink2}

# Shadowsocks gRPC
${shadowsockslink1}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $ntls
- Password: $uuid
- Method: $cipher
- Path: /ss-ws
- Service Name: ss-grpc
- Expiry: $exp (1 day trial)

END

    # Display results
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}        Trial Shadowsocks Account      ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "Remarks        : ${user} ${yellow}(TRIAL)${nc}"
    echo -e "IP             : ${MYIP}"
    echo -e "Domain         : ${domain}"
    echo -e "Wildcard       : bug.com.${domain}"
    echo -e "Port TLS       : ${tls}"
    echo -e "Port none TLS  : ${ntls}"
    echo -e "Port gRPC      : ${tls}"
    echo -e "Password       : ${uuid}"
    echo -e "Ciphers        : ${cipher}"
    echo -e "Network        : ws/grpc"
    echo -e "Path           : /ss-ws"
    echo -e "ServiceName    : ss-grpc"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link TLS (WS)${nc}"
    echo -e "${shadowsockslink}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link none TLS (WS)${nc}"
    echo -e "${shadowsockslink2}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link gRPC${nc}"
    echo -e "${shadowsockslink1}"
    echo -e "${red}=========================================${nc}"
    echo -e "Expired On     : $exp ${yellow}(1 day trial)${nc}"
    echo -e "Config File    : $CLIENT_DIR/ss-$user.txt"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Log the creation
    echo "$(date): Created trial SS account $user (exp: $exp)" >> /var/log/trial-ss.log
    
    echo -e "${green}SUCCESS${nc}: Trial Shadowsocks account created!"
    echo -e "${yellow}NOTE${nc}: This is a 1-day trial account"
else
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    echo -e "${yellow}Restoring backup config...${nc}"
    cp /etc/xray/config.json.backup.* /etc/xray/config.json 2>/dev/null
    systemctl restart xray > /dev/null 2>&1
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-ssws

