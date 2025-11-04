#!/bin/bash
# ==========================================
# Add Trojan Account - WITH gRPC SUPPORT - FIXED
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
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan WS TLS" | cut -d: -f2 | sed 's/ //g')"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan WS none TLS" | cut -d: -f2 | sed 's/ //g')"
grpc_port="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan gRPC" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Trojan WS ports in log file."
    exit 1
fi

# Check if gRPC is available
grpc_enabled=false
if [[ -n "$grpc_port" ]]; then
    grpc_enabled=true
    echo -e "${green}✓ gRPC support detected on port: $grpc_port${nc}"
else
    echo -e "${yellow}ℹ gRPC support not detected (optional)${nc}"
fi

# Function to validate username - FIXED
validate_username() {
    local user="$1"
    
    # Validate format
    if [[ ! $user =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}ERROR${nc}: Username can only contain letters, numbers and underscores"
        return 1
    fi
    
    # Check if user exists using jq - FIXED METHOD
    if command -v jq &> /dev/null; then
        # Check in Trojan WS
        local user_exists_ws=$(jq '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | select(.email == "'"$user"'") | .email' /usr/local/etc/xray/config.json 2>/dev/null)
        # Check in Trojan gRPC
        local user_exists_grpc=$(jq '.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients[] | select(.email == "'"$user"'") | .email' /usr/local/etc/xray/config.json 2>/dev/null)
        
        if [[ -n "$user_exists_ws" ]] || [[ -n "$user_exists_grpc" ]]; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    else
        # Fallback to grep - IMPROVED
        echo -e "${yellow}⚠ jq not found, using grep fallback${nc}"
        local user_exists=$(grep -o "\"email\":\"$user\"" /usr/local/etc/xray/config.json 2>/dev/null | wc -l)
        if [[ $user_exists -gt 0 ]]; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    fi
    
    return 0
}

# Function to check if trojan-grpc inbound exists - NEW FUNCTION
check_trojan_grpc_exists() {
    local config_file="$1"
    if jq '.inbounds[] | select(.tag == "trojan-grpc")' "$config_file" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to add user using jq - FIXED
add_trojan_user() {
    local user="$1"
    local uuid="$2"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        echo -e "${yellow}Installing jq...${nc}"
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo -e "${red}ERROR${nc}: Failed to install jq"
            return 1
        fi
    fi
    
    # Backup config
    backup_file="${config_file}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    echo -e "${yellow}Config backed up to: $backup_file${nc}"
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR${nc}: Config file not found: $config_file"
        return 1
    fi
    
    # Validate JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Invalid JSON in config file"
        return 1
    fi
    
    # Get current client count
    current_ws_clients=$(jq '[.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]] | length' "$config_file")
    echo -e "${yellow}Current Trojan WS clients: $current_ws_clients${nc}"
    
    # Add to Trojan WS - FIXED SYNTAX
    echo -e "${yellow}Adding user to Trojan WS...${nc}"
    if ! jq '(.inbounds[] | select(.tag == "trojan-ws").settings.clients) += [{"password": "'"$uuid"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp"; then
        echo -e "${red}ERROR${nc}: Failed to update Trojan WS (jq error)"
        return 1
    fi
    
    if [[ ! -f "${config_file}.tmp" ]]; then
        echo -e "${red}ERROR${nc}: Temporary file not created"
        return 1
    fi
    
    # Validate the temp file before replacing
    if ! jq empty "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Generated config has invalid JSON"
        rm -f "${config_file}.tmp"
        return 1
    fi
    
    mv "${config_file}.tmp" "$config_file"
    
    # Verify the user was added to WS
    local user_added_ws=$(jq '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
    
    if [[ "$user_added_ws" == "\"$user\"" ]]; then
        echo -e "${green}✓ User successfully added to Trojan WS${nc}"
    else
        echo -e "${red}ERROR${nc}: User not found in Trojan WS after update"
        return 1
    fi
    
    # Add to Trojan gRPC if enabled AND exists - FIXED CHECK
    if $grpc_enabled && check_trojan_grpc_exists "$config_file"; then
        echo -e "${yellow}Adding user to Trojan gRPC...${nc}"
        if jq '(.inbounds[] | select(.tag == "trojan-grpc").settings.clients) += [{"password": "'"$uuid"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp2"; then
            if jq empty "${config_file}.tmp2" 2>/dev/null; then
                mv "${config_file}.tmp2" "$config_file"
                
                # Verify the user was added to gRPC
                local user_added_grpc=$(jq '.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients[] | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
                
                if [[ "$user_added_grpc" == "\"$user\"" ]]; then
                    echo -e "${green}✓ User successfully added to Trojan gRPC${nc}"
                else
                    echo -e "${yellow}⚠ User not found in Trojan gRPC after update${nc}"
                fi
            else
                echo -e "${yellow}⚠ Invalid JSON generated for gRPC update${nc}"
                rm -f "${config_file}.tmp2"
            fi
        else
            echo -e "${yellow}⚠ Failed to update Trojan gRPC${nc}"
        fi
    elif $grpc_enabled; then
        echo -e "${yellow}⚠ Trojan gRPC tag not found in config, skipping${nc}"
    fi
    
    # Show final counts
    new_ws_clients=$(jq '[.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]] | length' "$config_file")
    echo -e "${yellow}New Trojan WS clients: $new_ws_clients${nc}"
    
    if $grpc_enabled && check_trojan_grpc_exists "$config_file"; then
        new_grpc_clients=$(jq '[.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients[]] | length' "$config_file")
        echo -e "${yellow}New Trojan gRPC clients: $new_grpc_clients${nc}"
    fi
    
    return 0
}

# Main user input loop
while true; do
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           TROJAN ACCOUNT CREATOR      ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${yellow}Info: Username must contain only letters, numbers, underscores${nc}"
    if $grpc_enabled; then
        echo -e "${green}✓ gRPC support available${nc}"
    else
        echo -e "${yellow}ℹ gRPC support not available${nc}"
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
done

# Generate UUID
uuid=$(cat /proc/sys/kernel/random/uuid)
echo -e "${green}Generated UUID: ${uuid}${nc}"

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
echo -e "${yellow}Account will expire on: $exp${nc}"

# Add user to config
echo -e "${yellow}Updating Xray configuration...${nc}"
if ! add_trojan_user "$user" "$uuid"; then
    echo -e "${red}ERROR${nc}: Failed to update config.json"
    echo -e "${yellow}Restoring backup...${nc}"
    latest_backup=$(ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        cp "$latest_backup" /usr/local/etc/xray/config.json
        echo -e "${green}✓ Config restored from backup${nc}"
    fi
    exit 1
fi

# Create Trojan links - FIXED: Use actual ports from config
trojanlink="trojan://${uuid}@${domain}:${tls}?path=%2Ftrojan-ws&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
trojanlink2="trojan://${uuid}@${domain}:${ntls}?path=%2Ftrojan-ws&security=none&host=${domain}&type=ws#${user}"

# Create gRPC link if enabled
if $grpc_enabled; then
    trojanlink3="trojan://${uuid}@${domain}:${grpc_port}?security=tls&type=grpc&serviceName=trojan-grpc&sni=${domain}#${user}-gRPC"
fi

# Restart Xray service with better error handling
echo -e "${yellow}Restarting Xray service...${nc}"
if systemctl restart xray; then
    echo -e "${green}✓ Xray service restarted successfully${nc}"
    
    # Wait and check if service is running
    sleep 5
    if systemctl is-active --quiet xray; then
        echo -e "${green}✓ Xray service is running properly${nc}"
        
        # Additional check: test config
        if /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
            echo -e "${green}✓ Xray config test passed${nc}"
        else
            echo -e "${red}✗ Xray config test failed${nc}"
        fi
    else
        echo -e "${red}✗ Xray service failed to start${nc}"
        echo -e "${yellow}Checking Xray status...${nc}"
        systemctl status xray --no-pager -l
        echo -e "${yellow}Restoring backup config...${nc}"
        latest_backup=$(ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" /usr/local/etc/xray/config.json
            systemctl restart xray
            echo -e "${green}✓ Config restored and Xray restarted${nc}"
        fi
        exit 1
    fi
else
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    systemctl status xray --no-pager -l
    exit 1
fi

# Create client config file
CLIENT_DIR="/home/vps/public_html"
mkdir -p "$CLIENT_DIR"

# Create configuration file
cat > "$CLIENT_DIR/trojan-$user.txt" <<-END
# ==========================================
# Trojan Client Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp
# ==========================================

# Trojan WS TLS
${trojanlink}

# Trojan WS None TLS
${trojanlink2}

END

# Add gRPC section if enabled
if $grpc_enabled; then
cat >> "$CLIENT_DIR/trojan-$user.txt" <<-END
# Trojan gRPC
${trojanlink3}

END
fi

# Add configuration details
cat >> "$CLIENT_DIR/trojan-$user.txt" <<-END
# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $ntls
END

if $grpc_enabled; then
cat >> "$CLIENT_DIR/trojan-$user.txt" <<-END
- Port gRPC: $grpc_port
END
fi

cat >> "$CLIENT_DIR/trojan-$user.txt" <<-END
- Password: $uuid
- Expiry: $exp

# For V2RayN / V2RayNG (WS):
- Address: $domain
- Port: $tls (TLS) / $ntls (None TLS)
- Password: $uuid
- Transport: WebSocket
- Path: /trojan-ws
- Host: $domain

END

if $grpc_enabled; then
cat >> "$CLIENT_DIR/trojan-$user.txt" <<-END
# For supporting gRPC clients:
- Address: $domain
- Port: $grpc_port
- Password: $uuid
- Transport: gRPC
- Service Name: trojan-grpc
- Host: $domain

END
fi

# Display results
clear
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
echo -e "${blue}           TROJAN ACCOUNT CREATED     ${nc}" | tee -a /var/log/create-trojan.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
echo -e "Remarks        : ${user}" | tee -a /var/log/create-trojan.log
echo -e "IP             : ${MYIP}" | tee -a /var/log/create-trojan.log
echo -e "Domain         : ${domain}" | tee -a /var/log/create-trojan.log
echo -e "Port TLS       : ${tls}" | tee -a /var/log/create-trojan.log
echo -e "Port none TLS  : ${ntls}" | tee -a /var/log/create-trojan.log
if $grpc_enabled; then
echo -e "Port gRPC      : ${grpc_port}" | tee -a /var/log/create-trojan.log
fi
echo -e "Password       : ${uuid}" | tee -a /var/log/create-trojan.log
echo -e "Expired On     : $exp" | tee -a /var/log/create-trojan.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
echo -e "${green}Link TLS (WS)${nc}" | tee -a /var/log/create-trojan.log
echo -e "${trojanlink}" | tee -a /var/log/create-trojan.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
echo -e "${green}Link none TLS (WS)${nc}" | tee -a /var/log/create-trojan.log
echo -e "${trojanlink2}" | tee -a /var/log/create-trojan.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
if $grpc_enabled; then
echo -e "${green}Link gRPC${nc}" | tee -a /var/log/create-trojan.log
echo -e "${trojanlink3}" | tee -a /var/log/create-trojan.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
fi
echo -e "Config File    : $CLIENT_DIR/trojan-$user.txt" | tee -a /var/log/create-trojan.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-trojan.log
echo "" | tee -a /var/log/create-trojan.log

# Clean up old backups (keep last 5)
ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | tail -n +6 | xargs -r rm

echo -e "${green}SUCCESS${nc}: Trojan account $user created successfully!"

read -n 1 -s -r -p "Press any key to back on menu"
m-trojan
