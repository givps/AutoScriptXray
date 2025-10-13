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
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "unknown")
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null || echo "unknown")

clear

# Function to backup config
backup_config() {
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        echo "error"
        return 1
    fi
    local backup_file="/usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S)"
    if cp /usr/local/etc/xray/config.json "$backup_file" 2>/dev/null; then
        echo "$backup_file"
    else
        echo "error"
    fi
}

# Function to restore config
restore_config() {
    local backup_file="$1"
    if [[ -f "$backup_file" && -f "/usr/local/etc/xray/config.json" ]]; then
        cp "$backup_file" /usr/local/etc/xray/config.json
        rm -f "$backup_file"
        return 0
    fi
    return 1
}

# Function to add user to config
add_user_to_config() {
    local user="$1"
    local uuid="$2"
    local exp="$3"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Add user to vmess-ws and vmess-grpc sections using awk
    awk -v user="$user" -v uuid="$uuid" -v exp="$exp" '
    /#vmess$/ {
        print $0
        print "### " user " " exp
        print "},{\"id\": \"" uuid "\",\"alterId\": 0,\"email\": \"" user "\""
        next
    }
    /#vmessgrpc$/ {
        print $0
        print "### " user " " exp
        print "},{\"id\": \"" uuid "\",\"alterId\": 0,\"email\": \"" user "\""
        next
    }
    { print }
    ' "$config_file" > "$temp_file"
    
    # Verify the addition worked
    if grep -q "^### $user $exp$" "$temp_file" && \
       grep -q "\"email\": \"$user\"" "$temp_file"; then
        # Verify JSON validity
        if python3 -m json.tool "$temp_file" > /dev/null 2>&1; then
            mv "$temp_file" "$config_file"
            chmod 644 "$config_file"
            return 0
        else
            rm -f "$temp_file"
            return 1
        fi
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}        Trial VMess Account           ${nc}"
echo -e "${red}=========================================${nc}"

# Validate domain exists
if [[ -z "$domain" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"
none="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS none TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VMess ports in log file."
    echo -e "${yellow}Please check if VMess is properly installed.${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Generate trial user
user="trial$(</dev/urandom tr -dc A-Z0-9 | head -c4 2>/dev/null || echo $RANDOM | md5sum | head -c4)"
uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "fallback-$(date +%s)")

if [[ -z "$uuid" ]]; then
    echo -e "${red}ERROR${nc}: Failed to generate UUID"
    exit 1
fi

masaaktif=1
exp=$(date -d "$masaaktif days" +"%Y-%m-%d" 2>/dev/null || date -v+1d "+%Y-%m-%d" 2>/dev/null || echo "unknown")

# Backup config before modification
echo -e "${yellow}Creating backup...${nc}"
backup_file=$(backup_config)

if [[ "$backup_file" == "error" ]]; then
    echo -e "${red}ERROR${nc}: Failed to create backup!"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Add user to config.json
echo -e "${yellow}Adding user to config...${nc}"
if add_user_to_config "$user" "$uuid" "$exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray > /dev/null 2>&1; then
        # Create VMess JSON configurations dengan domain yang benar (bukan bug.com)
        wstls=$(cat<<EOF
{
  "v": "2",
  "ps": "${user}",
  "add": "${domain}",
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
  "add": "${domain}",
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
  "host": "${domain}",
  "tls": "tls",
  "sni": "${domain}"
}
EOF
)

        # Create VMess links
        vmesslink1="vmess://$(echo "$wstls" | base64 -w 0 2>/dev/null || echo "$wstls" | base64 2>/dev/null || echo "base64_error")"
        vmesslink2="vmess://$(echo "$wsnontls" | base64 -w 0 2>/dev/null || echo "$wsnontls" | base64 2>/dev/null || echo "base64_error")"
        vmesslink3="vmess://$(echo "$grpc" | base64 -w 0 2>/dev/null || echo "$grpc" | base64 2>/dev/null || echo "base64_error")"

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
- Address: $domain
- Port: $tls (TLS) / $none (None TLS)
- UUID: $uuid
- Alter ID: 0
- Security: auto
- Transport: WebSocket (WS) / gRPC
- Path: /vmess
- Host: $domain
- SNI: $domain (for TLS)

END

        # Display results
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}        Trial VMess Account           ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}✓ Trial VMess Account Created Successfully${nc}"
        echo ""
        echo -e "${blue}Account Details:${nc}"
        echo -e "  • Remarks       : ${user} ${yellow}(TRIAL)${nc}"
        echo -e "  • Domain        : ${domain}"
        echo -e "  • Port TLS      : ${tls}"
        echo -e "  • Port Non-TLS  : ${none}"
        echo -e "  • UUID          : ${uuid}"
        echo -e "  • Alter ID      : 0"
        echo -e "  • Security      : auto"
        echo -e "  • Network       : WS/gRPC"
        echo -e "  • Path WS       : /vmess"
        echo -e "  • Service Name  : vmess-grpc"
        echo -e "  • Expiry        : $exp ${yellow}(1 day trial)${nc}"
        echo ""
        
        echo -e "${green}Configuration Links:${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}VMess WS with TLS:${nc}"
        echo -e "${vmesslink1}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}VMess WS without TLS:${nc}"
        echo -e "${vmesslink2}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}VMess gRPC:${nc}"
        echo -e "${vmesslink3}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${blue}Config File:${nc} $CLIENT_DIR/vmess-$user.txt"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
        
        # Log the creation
        echo "$(date): Created trial VMess account $user (UUID: $uuid, exp: $exp)" >> /var/log/trial-vmess.log 2>/dev/null
        
        echo -e "${green}SUCCESS${nc}: Trial VMess account created!"
        echo -e "${yellow}NOTE${nc}: This is a 1-day trial account"
        
    else
        echo -e "${red}ERROR${nc}: Failed to restart Xray service"
        echo -e "${yellow}Restoring backup config...${nc}"
        restore_config "$backup_file"
        systemctl restart xray > /dev/null 2>&1
        echo -e "${red}Changes have been reverted${nc}"
    fi
else
    echo -e "${red}ERROR${nc}: Failed to add user to config"
    echo -e "${yellow}Restoring backup config...${nc}"
    restore_config "$backup_file"
    echo -e "${red}No changes were made${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess 2>/dev/null || exit 0
