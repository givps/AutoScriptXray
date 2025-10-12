#!/bin/bash
# ==========================================
# Add VLess Account
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

# Function to validate username
validate_username() {
    local user="$1"
    if [[ ! $user =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}ERROR${nc}: Username can only contain letters, numbers and underscores"
        return 1
    fi
    
    local client_exists=$(grep -w "$user" /usr/local/etc/xray/config.json 2>/dev/null | wc -l)
    if [[ $client_exists -gt 0 ]]; then
        echo -e "${red}ERROR${nc}: User $user already exists"
        return 1
    fi
    
    return 0
}

# Main user input loop
while true; do
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           VLess ACCOUNT          ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${yellow}Info: Username must contain only letters, numbers, underscores${nc}"
    echo ""
    
    read -rp "Username: " user
    
    if validate_username "$user"; then
        break
    fi
    
    echo ""
    echo -e "${red}Please choose a different username${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    clear
done

# Generate UUID
uuid=$(cat /proc/sys/kernel/random/uuid)

# Get expiry date with validation
while true; do
    read -p "Expired (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [ $masaaktif -gt 0 ]; then
        break
    else
        echo -e "${red}ERROR${nc}: Please enter a valid number of days"
    fi
done

exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# Backup config file before modification
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

# Create VLess links
vlesslink1="vless://${uuid}@bug.com:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}"
vlesslink2="vless://${uuid}@bug.com:${none}?path=%2Fvless&security=none&encryption=none&type=ws&host=${domain}#${user}"
vlesslink3="vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=bug.com#${user}"

# Restart Xray service
if ! systemctl restart xray; then
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    echo -e "${yellow}INFO${nc}: Restoring backup config..."
    cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
    systemctl restart xray
    exit 1
fi

# Create client config file
CLIENT_DIR="/home/vps/public_html"
mkdir -p "$CLIENT_DIR"

cat > "$CLIENT_DIR/vless-$user.txt" <<-END
# ==========================================
# VLess Client Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp
# ==========================================

# VLess WS TLS
vless://${uuid}@bug.com:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}

# VLess WS None TLS
vless://${uuid}@bug.com:${none}?path=%2Fvless&security=none&encryption=none&type=ws&host=${domain}#${user}

# VLess gRPC
vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=bug.com#${user}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $none
- UUID: $uuid
- Encryption: none
- Path WS: /vless
- Service Name gRPC: vless-grpc
- Expiry: $exp

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
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo -e "${blue}           VLess ACCOUNT           ${nc}" | tee -a /var/log/create-vless.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo -e "Remarks        : ${user}" | tee -a /var/log/create-vless.log
echo -e "IP             : ${MYIP}" | tee -a /var/log/create-vless.log
echo -e "Domain         : ${domain}" | tee -a /var/log/create-vless.log
echo -e "Wildcard       : bug.com.${domain}" | tee -a /var/log/create-vless.log
echo -e "Port TLS       : ${tls}" | tee -a /var/log/create-vless.log
echo -e "Port none TLS  : ${none}" | tee -a /var/log/create-vless.log
echo -e "Port gRPC      : ${tls}" | tee -a /var/log/create-vless.log
echo -e "Password       : ${uuid}" | tee -a /var/log/create-vless.log
echo -e "Encryption     : none" | tee -a /var/log/create-vless.log
echo -e "Network        : ws/grpc" | tee -a /var/log/create-vless.log
echo -e "Path WS        : /vless" | tee -a /var/log/create-vless.log
echo -e "ServiceName    : vless-grpc" | tee -a /var/log/create-vless.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo -e "${green}Link TLS (WS)${nc}" | tee -a /var/log/create-vless.log
echo -e "${vlesslink1}" | tee -a /var/log/create-vless.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo -e "${green}Link none TLS (WS)${nc}" | tee -a /var/log/create-vless.log
echo -e "${vlesslink2}" | tee -a /var/log/create-vless.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo -e "${green}Link gRPC${nc}" | tee -a /var/log/create-vless.log
echo -e "${vlesslink3}" | tee -a /var/log/create-vless.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo -e "Expired On     : $exp" | tee -a /var/log/create-vless.log
echo -e "Config File    : $CLIENT_DIR/vless-$user.txt" | tee -a /var/log/create-vless.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vless.log
echo "" | tee -a /var/log/create-vless.log

# Clean up old backups (keep last 5)
ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | tail -n +6 | xargs -r rm

echo -e "${green}SUCCESS${nc}: VLess account $user created successfully!"
echo -e "${yellow}INFO${nc}: Configuration backup created"

read -n 1 -s -r -p "Press any key to back on menu"

m-vless
