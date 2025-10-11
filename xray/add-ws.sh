#!/bin/bash
# ==========================================
# Add VMess Account
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
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS TLS" | cut -d: -f2 | sed 's/ //g')"
none="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VMess ports in log file."
    exit 1
fi

# Function to validate username
validate_username() {
    local user="$1"
    if [[ ! $user =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}ERROR${nc}: Username can only contain letters, numbers and underscores"
        return 1
    fi
    
    local client_exists=$(grep -w "$user" /etc/xray/config.json 2>/dev/null | wc -l)
    if [[ $client_exists -gt 0 ]]; then
        echo -e "${red}ERROR${nc}: User $user already exists"
        return 1
    fi
    
    return 0
}

# Main user input loop
while true; do
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           VMESS ACCOUNT          ${nc}"
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

# Create VMess JSON configurations
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
if ! systemctl restart xray; then
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    echo -e "${yellow}INFO${nc}: Restoring backup config..."
    cp /etc/xray/config.json.backup.* /etc/xray/config.json 2>/dev/null
    systemctl restart xray
    exit 1
fi

# Restart cron quietly
service cron restart > /dev/null 2>&1

# Create client config file
CLIENT_DIR="/home/vps/public_html"
mkdir -p "$CLIENT_DIR"

cat > "$CLIENT_DIR/vmess-$user.txt" <<-END
# ==========================================
# VMess Client Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp
# ==========================================

# VMess WS TLS
$vmesslink1

# VMess WS None TLS  
$vmesslink2

# VMess gRPC
$vmesslink3

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
- Expiry: $exp

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
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo -e "${blue}           VMESS ACCOUNT           ${nc}" | tee -a /var/log/create-vmess.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo -e "Remarks        : ${user}" | tee -a /var/log/create-vmess.log
echo -e "IP             : ${MYIP}" | tee -a /var/log/create-vmess.log
echo -e "Domain         : ${domain}" | tee -a /var/log/create-vmess.log
echo -e "Wildcard       : bug.com.${domain}" | tee -a /var/log/create-vmess.log
echo -e "Port TLS       : ${tls}" | tee -a /var/log/create-vmess.log
echo -e "Port none TLS  : ${none}" | tee -a /var/log/create-vmess.log
echo -e "Port gRPC      : ${tls}" | tee -a /var/log/create-vmess.log
echo -e "User ID        : ${uuid}" | tee -a /var/log/create-vmess.log
echo -e "Alter ID       : 0" | tee -a /var/log/create-vmess.log
echo -e "Security       : auto" | tee -a /var/log/create-vmess.log
echo -e "Network        : ws/grpc" | tee -a /var/log/create-vmess.log
echo -e "Path WS        : /vmess" | tee -a /var/log/create-vmess.log
echo -e "ServiceName    : vmess-grpc" | tee -a /var/log/create-vmess.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo -e "${green}Link TLS (WS)${nc}" | tee -a /var/log/create-vmess.log
echo -e "${vmesslink1}" | tee -a /var/log/create-vmess.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo -e "${green}Link none TLS (WS)${nc}" | tee -a /var/log/create-vmess.log
echo -e "${vmesslink2}" | tee -a /var/log/create-vmess.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo -e "${green}Link gRPC${nc}" | tee -a /var/log/create-vmess.log
echo -e "${vmesslink3}" | tee -a /var/log/create-vmess.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo -e "Expired On     : $exp" | tee -a /var/log/create-vmess.log
echo -e "Config File    : $CLIENT_DIR/vmess-$user.txt" | tee -a /var/log/create-vmess.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
echo "" | tee -a /var/log/create-vmess.log

# Clean up old backups (keep last 5)
ls -t /etc/xray/config.json.backup.* 2>/dev/null | tail -n +6 | xargs -r rm

echo -e "${green}SUCCESS${nc}: VMess account $user created successfully!"
echo -e "${yellow}INFO${nc}: Configuration backup created"

read -n 1 -s -r -p "Press any key to back on menu"
m-vmess

