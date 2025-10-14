#!/bin/bash
# ==========================================
# Add VLess Account - FIXED VERSION
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

# Function to add user to config using jq (proper JSON handling)
add_user_to_config() {
    local user="$1"
    local uuid="$2"
    local exp="$3"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found${nc}" >&2
        return 1
    fi
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        echo -e "${yellow}Installing jq for JSON processing...${nc}"
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Validate JSON first
    if ! jq empty "$config_file" > /dev/null 2>&1; then
        echo -e "${red}ERROR: Invalid JSON in config file${nc}" >&2
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Add user to vless-ws
    echo -e "${yellow}Adding user to VLess WS...${nc}"
    if jq -e '.inbounds[] | select(.tag == "vless-ws")' "$config_file" > /dev/null 2>&1; then
        jq '(.inbounds[] | select(.tag == "vless-ws").settings.clients) += [{"id": "'"$uuid"'", "email": "'"$user"'"}]' "$config_file" > "$temp_file"
        if [[ $? -ne 0 ]]; then
            echo -e "${red}ERROR: Failed to add user to VLess WS${nc}" >&2
            rm -f "$temp_file"
            return 1
        fi
        mv "$temp_file" "$config_file"
    else
        echo -e "${yellow}Warning: VLess WS inbound not found${nc}" >&2
    fi
    
    # Add user to vless-grpc if exists
    echo -e "${yellow}Adding user to VLess gRPC...${nc}"
    if jq -e '.inbounds[] | select(.tag == "vless-grpc")' "$config_file" > /dev/null 2>&1; then
        jq '(.inbounds[] | select(.tag == "vless-grpc").settings.clients) += [{"id": "'"$uuid"'", "email": "'"$user"'"}]' "$config_file" > "$temp_file"
        if [[ $? -eq 0 ]]; then
            mv "$temp_file" "$config_file"
            echo -e "${green}✓ User added to VLess gRPC${nc}"
        else
            echo -e "${yellow}Warning: Failed to add user to VLess gRPC${nc}" >&2
        fi
    else
        echo -e "${yellow}Info: VLess gRPC inbound not found (optional)${nc}" >&2
    fi
    
    # Add expiry comment
    echo -e "${yellow}Adding expiry comment...${nc}"
    if grep -q "^#! $user " "$config_file" 2>/dev/null; then
        sed -i "s/^#! $user .*/#! $user $exp/g" "$config_file"
    else
        # Find a good place to insert the comment (after clients array)
        local insert_line=$(grep -n '"clients": \[' "$config_file" | head -1 | cut -d: -f1)
        if [[ -n "$insert_line" ]]; then
            sed -i "${insert_line}a #! $user $exp" "$config_file"
        else
            # Fallback: add to end of file
            echo "#! $user $exp" >> "$config_file"
        fi
    fi
    
    # Verify the user was added
    if jq -e '.inbounds[] | select(.tag == "vless-ws") | .settings.clients[] | select(.email == "'"$user"'")' "$config_file" > /dev/null 2>&1; then
        echo -e "${green}✓ User successfully added to VLess WS${nc}"
        
        # Count current users
        local user_count=$(jq '[.inbounds[] | select(.tag == "vless-ws") | .settings.clients[]] | length' "$config_file")
        echo -e "${yellow}Current VLess WS users: $user_count${nc}"
        
        return 0
    else
        echo -e "${red}ERROR: User not found in config after update${nc}" >&2
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
    
    # Check if username already exists using jq
    if command -v jq &> /dev/null && [[ -f "/usr/local/etc/xray/config.json" ]]; then
        if jq -e '.inbounds[] | .settings.clients[] | select(.email == "'"$user"'")' "/usr/local/etc/xray/config.json" > /dev/null 2>&1; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    else
        # Fallback to grep
        if grep -q "\"email\": \"$user\"" /usr/local/etc/xray/config.json 2>/dev/null; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    fi
    
    return 0
}

# Function to get service status
check_xray_status() {
    if systemctl is-active --quiet xray; then
        echo -e "${green}active${nc}"
        return 0
    else
        echo -e "${red}inactive${nc}"
        return 1
    fi
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}           CREATE VLess ACCOUNT        ${nc}"
echo -e "${red}=========================================${nc}"

# Check Xray status
echo -e "${yellow}Checking Xray service status...${nc}"
xray_status=$(check_xray_status)
echo -e "Xray service: $xray_status"

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
grpc_port="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vless gRPC" | cut -d: -f2 | sed 's/ //g' | head -1)"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VLess ports in log file."
    echo -e "${yellow}Please check if VLess is properly installed.${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Check gRPC availability
grpc_enabled=false
if [[ -n "$grpc_port" ]]; then
    grpc_enabled=true
    echo -e "${green}✓ gRPC support detected on port: $grpc_port${nc}"
else
    echo -e "${yellow}ℹ gRPC support not detected (optional)${nc}"
fi

# Main user input loop
while true; do
    echo ""
    echo -e "${yellow}Info: Username must contain only letters, numbers, underscores${nc}"
    if $grpc_enabled; then
        echo -e "${green}✓ gRPC support available${nc}"
    fi
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
    echo -e "${blue}           CREATE VLess ACCOUNT        ${nc}"
    echo -e "${red}=========================================${nc}"
done

# Generate UUID
echo -e "${yellow}Generating UUID...${nc}"
uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || openssl rand -hex 16 2>/dev/null || echo "fallback-$(date +%s)")

if [[ -z "$uuid" ]] || [[ "$uuid" == "fallback-"* ]]; then
    echo -e "${red}ERROR${nc}: Failed to generate valid UUID"
    exit 1
fi

echo -e "${green}Generated UUID: $uuid${nc}"

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
echo -e "${yellow}Account will expire on: $exp${nc}"

# Backup config before modification
echo -e "${yellow}Creating backup...${nc}"
backup_file=$(backup_config)

if [[ "$backup_file" == "error" ]]; then
    echo -e "${red}ERROR${nc}: Failed to create backup!"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

echo -e "${green}✓ Backup created: $backup_file${nc}"

# Add user to config.json
echo -e "${yellow}Updating Xray configuration...${nc}"
if add_user_to_config "$user" "$uuid" "$exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray > /dev/null 2>&1; then
        sleep 2
        if systemctl is-active --quiet xray; then
            echo -e "${green}✓ Xray service restarted successfully${nc}"
            
            # Create VLess links with correct domain
            vlesslink1="vless://${uuid}@${domain}:${tls}?path=%2Fvless&security=tls&encryption=none&type=ws&sni=${domain}#${user}"
            vlesslink2="vless://${uuid}@${domain}:${none}?path=%2Fvless&security=none&encryption=none&type=ws&host=${domain}#${user}"
            
            # Add gRPC link if enabled
            if $grpc_enabled; then
                vlesslink3="vless://${uuid}@${domain}:${grpc_port}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}"
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
${vlesslink1}

# VLess WS None TLS
${vlesslink2}

END

            if $grpc_enabled; then
                cat >> "$CLIENT_DIR/vless-$user.txt" <<-END
# VLess gRPC
${vlesslink3}

END
            fi

            cat >> "$CLIENT_DIR/vless-$user.txt" <<-END
# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $none
END

            if $grpc_enabled; then
                cat >> "$CLIENT_DIR/vless-$user.txt" <<-END
- Port gRPC: $grpc_port
END
            fi

            cat >> "$CLIENT_DIR/vless-$user.txt" <<-END
- UUID: $uuid
- Encryption: none
- Path WS: /vless
END

            if $grpc_enabled; then
                cat >> "$CLIENT_DIR/vless-$user.txt" <<-END
- Service Name gRPC: vless-grpc
END
            fi

            cat >> "$CLIENT_DIR/vless-$user.txt" <<-END
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
            echo -e "${blue}           VLess ACCOUNT CREATED       ${nc}"
            echo -e "${red}=========================================${nc}"
            echo -e "${green}✓ VLess Account Created Successfully${nc}"
            echo ""
            echo -e "${blue}Account Details:${nc}"
            echo -e "  • Remarks       : ${user}"
            echo -e "  • Domain        : ${domain}"
            echo -e "  • Port TLS      : ${tls}"
            echo -e "  • Port Non-TLS  : ${none}"
            if $grpc_enabled; then
                echo -e "  • Port gRPC     : ${grpc_port}"
            fi
            echo -e "  • UUID          : ${uuid}"
            echo -e "  • Encryption    : none"
            echo -e "  • Network       : WS"
            if $grpc_enabled; then
                echo -e "  • Network       : WS + gRPC"
            fi
            echo -e "  • Path WS       : /vless"
            if $grpc_enabled; then
                echo -e "  • Service Name  : vless-grpc"
            fi
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
            if $grpc_enabled; then
                echo -e "${yellow}VLess gRPC:${nc}"
                echo -e "${vlesslink3}"
                echo -e "${red}=========================================${nc}"
            fi
            echo ""
            echo -e "${blue}Config File:${nc} $CLIENT_DIR/vless-$user.txt"
            echo -e "${red}=========================================${nc}"
            
            # Clean up backup file
            rm -f "$backup_file" 2>/dev/null
            
            # Log the creation
            echo "$(date): Created VLess account $user (UUID: $uuid, exp: $exp)" >> /var/log/create-vless.log 2>/dev/null
            
            echo -e "${green}SUCCESS${nc}: VLess account $user created successfully!"
            
        else
            echo -e "${red}ERROR${nc}: Xray service failed to start after restart"
            echo -e "${yellow}Restoring backup config...${nc}"
            restore_config "$backup_file"
            systemctl restart xray > /dev/null 2>&1
            echo -e "${red}Changes have been reverted${nc}"
        fi
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
