#!/bin/bash
# ==========================================
# Create Trial VMess Account
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
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS TLS" | cut -d: -f2 | sed 's/ //g')"
none="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VMess ports in log file."
    exit 1
fi

# Generate trial user
user="trial$(</dev/urandom tr -dc A-Z0-9 | head -c4)"
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=1
exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# Backup config before modification
cp /etc/xray/config.json /etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Add user to config.json for WS
if ! sed -i '/#vmess$/a\### '"$user $exp"'\
},{"id": "'"$uuid"'","alterId": 0,"email": "'"$user"'"' /etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for VMess WS"
    exit 1
fi

# Add user to config.json for gRPC
if ! sed -i '/#vmessgrpc$/a\### '"$user $exp"'\
},{"id": "'"$uuid"'","alterId": 0,"email": "'"$user"'"' /etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for VMess gRPC"
    # Restore backup on error
    cp /etc/xray/config.json.backup.* /etc/xray/config.json 2>/dev/null
    exit 1
fi

# Create VMess JSON configurations dengan parameter yang benar
wstls=$(cat<<EOF
{
  "v": "2",
  "ps": "${user}",
  "add": "bug.com",
  "port": "${tls}",
  "id": "${uuid}",
  "aid": "0",
  "net": "ws",
  "path": "/vmess",
  "type": "none",
  "host": "${domain}",
  "tls": "tls",
  "sni": "${domain}"
}
EOF
)

wsnontls=$(cat<<EOF
{
  "v": "2",
  "ps": "${user}",
  "add": "bug.com",
  "port": "${none}",
  "id": "${uuid}",
  "aid": "0",
  "net": "ws",
  "path": "/vmess",
  "type": "none",
  "host": "${domain}",
  "tls": "none"
}
EOF
)

grpc=$(cat<<EOF
{
  "v": "2",
  "ps": "${user}",
  "add": "${domain}",
  "port": "${tls}",
  "id": "${uuid}",
  "aid": "0",
  "net": "grpc",
  "path": "vmess-grpc",
  "type": "none",
  "host": "",
  "tls": "tls",
  "sni": "bug.com"
}
EOF
)

# Create VMess links
vmesslink1="vmess://$(echo "$wstls" | base64 -w 0)"
vmesslink2="vmess://$(echo "$wsnontls" | base64 -w 0)"
vmesslink3="vmess://$(echo "$grpc" | base64 -w 0)"

# Restart Xray service
if systemctl restart xray > /dev/null 2>&1; then
    service cron restart > /dev/null 2>&1
    
    # Create client config file
    CLIENT_DIR="/home/vps/public_html"
    mkdir -p "$CLIENT_DIR"
    
    cat > "$CLIENT_DIR/vmess-$user.txt" <<-END
# ==========================================
# VMess Trial Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp (1 day trial)
# ==========================================

# VMess WS TLS
${vmesslink1}

# VMess WS None TLS  
${vmesslink2}

# VMess gRPC
${vmesslink3}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $none
- UUID: $uuid
- Alter ID: 0
- Security: auto
- Network: ws/grpc
- Path WS: /vmess
- Service Name gRPC: vmess-grpc
- Expiry: $exp (1 day trial)

# For V2RayN / V2RayNG:
- Address: bug.com (TLS) / bug.com (None TLS)
- Port: $tls (TLS) / $none (None TLS)
- UUID: $uuid
- Alter ID: 0
- Security: auto
- Transport: WebSocket (WS) / gRPC
- Path: /vmess
- Host: $domain

END

    # Display results
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           TRIAL VMESS           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "Remarks        : ${user} ${yellow}(TRIAL)${nc}"
    echo -e "IP             : ${MYIP}"
    echo -e "Domain         : ${domain}"
    echo -e "Wildcard       : bug.com.${domain}"
    echo -e "Port TLS       : ${tls}"
    echo -e "Port none TLS  : ${none}"
    echo -e "Port gRPC      : ${tls}"
    echo -e "Password       : ${uuid}"
    echo -e "Alter ID       : 0"
    echo -e "Security       : auto"
    echo -e "Network        : ws/grpc"
    echo -e "Path WS        : /vmess"
    echo -e "ServiceName    : vmess-grpc"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link TLS (WS)${nc}"
    echo -e "${vmesslink1}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link none TLS (WS)${nc}"
    echo -e "${vmesslink2}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}Link gRPC${nc}"
    echo -e "${vmesslink3}"
    echo -e "${red}=========================================${nc}"
    echo -e "Expired On     : $exp ${yellow}(1 day trial)${nc}"
    echo -e "Config File    : $CLIENT_DIR/vmess-$user.txt"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Log the creation
    echo "$(date): Created trial VMess account $user (exp: $exp)" >> /var/log/trial-vmess.log
    
    echo -e "${green}SUCCESS${nc}: Trial VMess account created!"
    echo -e "${yellow}NOTE${nc}: This is a 1-day trial account"
else
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    echo -e "${yellow}Restoring backup config...${nc}"
    cp /etc/xray/config.json.backup.* /etc/xray/config.json 2>/dev/null
    systemctl restart xray > /dev/null 2>&1
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess

