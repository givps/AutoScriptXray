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
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "unknown")
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

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
    
    # Add user to vless-ws and vless-grpc sections using awk
    awk -v user="$user" -v uuid="$uuid" -v exp="$exp" '
    /#vless$/ {
        print $0
        print "### " user " " exp
        print "},{\"id\": \"" uuid "\",\"email\": \"" user "\""
        next
    }
    /#vlessgrpc$/ {
        print $0
        print "### " user " " exp
        print "},{\"id\": \"" uuid "\",\"email\": \"" user "\""
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

# Function to validate username
validate_username() {
    local user="$1"
    
    # Check if username is empty
    if [[ -z "$user" ]]; then
        echo -e "${red}ERROR${nc}: Username cannot be empty"
        return 1
    fi
    
    # Check username format (letters, numbers, underscores only)
    if [[ ! $user =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}ERROR${nc}: Username can only contain letters, numbers and underscores"
        return 1
    fi
    
    # Check if username already exists
    if grep -q "\"email\": \"$user\"" /usr/local/etc/xray/config.json 2>/dev/null; then
        echo -e "${red}ERROR${nc}: User $user already exists"
        return 1
    fi
    
    return 0
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}           VLess ACCOUNT           ${nc}"
echo -e "${red}=========================================${nc}"

# Validate domain exists
if [[ -z "$domain" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vless WS TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"
none="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vless WS none TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VLess ports in log file."
    echo -e "${yellow}Please check if VLess is properly installed.${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Main user input loop
while true; do
    echo ""
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
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           VLess ACCOUNT           ${nc}"
    echo -e "${red}=========================================${nc}"
done

# Generate UUID
uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "fallback-$(date +%s)")

if [[ -z "$uuid" ]]; then
    echo -e "${red}ERROR${nc}: Failed to generate UUID"
    exit 1
fi

# Get expiry date with validation
while true; do
    echo ""
    read -p "Expired (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [ $masaaktif -gt 0 ] && [ $masaaktif -le 3650 ]; then
        break
    else
        echo -e "${red}ERROR${nc}: Please enter a valid number of days (1-3650)"
    fi
done

exp=$(date -d "$masaaktif days" +"%Y-%m-%d" 2>/dev/null || date -v+"$masaaktif"d "+%Y-%m-%d" 2>/dev/null || echo "unknown")

# Backup config before modification
echo -e "${yellow}Creating backup...${nc}"
backup_file=$(backup_config)

if [[ "$backup_file" == "error" ]]; then
    echo -e "${red}ERROR${nc}: Failed to create backup!"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Add user to config.json
echo -e "${yellow}Adding user to config...${nc}"
if add_user_to_config "$user" "$uuid" "$exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray > /dev/null 2>&1; then
        # Create VLess links with correct domain
        vlesslink1="vless://${uuid}@${domain}:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}"
        vlesslink2="vless://${uuid}@${domain}:${none}?path=%2Fvless&security=none&encryption=none&type=ws&host=${domain}#${user}"
        vlesslink3="vless://${uuid}@${domain}:${tls}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"

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
- Expiry: $exp

# For V2RayN / V2RayNG:
- Address: $domain
- Port: $tls (TLS) / $none (None TLS)
- UUID: $uuid
- Encryption: none
- Transport: WebSocket (WS) / gRPC
- Path: /vless
- Host: $domain
- SNI: $domain (for TLS)

END

        # Display results
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}           VLess ACCOUNT           ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}✓ VLess Account Created Successfully${nc}"
        echo ""
        echo -e "${blue}Account Details:${nc}"
        echo -e "  • Remarks       : ${user}"
        echo -e "  • Domain        : ${domain}"
        echo -e "  • Port TLS      : ${tls}"
        echo -e "  • Port Non-TLS  : ${none}"
        echo -e "  • UUID          : ${uuid}"
        echo -e "  • Encryption    : none"
        echo -e "  • Network       : WS/gRPC"
        echo -e "  • Path WS       : /vless"
        echo -e "  • Service Name  : vless-grpc"
        echo -e "  • Expiry        : $exp"
        echo ""
        
        echo -e "${green}Configuration Links:${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}VLess WS with TLS:${nc}"
        echo -e "${vlesslink1}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}VLess WS without TLS:${nc}"
        echo -e "${vlesslink2}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}VLess gRPC:${nc}"
        echo -e "${vlesslink3}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${blue}Config File:${nc} $CLIENT_DIR/vless-$user.txt"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
        
        # Log the creation
        echo "$(date): Created VLess account $user (UUID: $uuid, exp: $exp)" >> /var/log/create-vless.log 2>/dev/null
        
        echo -e "${green}SUCCESS${nc}: VLess account $user created successfully!"
        
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
m-vless 2>/dev/null || exit 0
