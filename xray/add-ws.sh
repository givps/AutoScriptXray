#!/bin/bash
# ==========================================
# Add VMess Account - FIXED VERSION
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

# Function to get VMess users using jq - FIXED
get_vmess_users() {
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found${nc}" >&2
        return 1
    fi
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        echo -e "${yellow}Installing jq...${nc}" >&2
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Check if config has valid JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${red}ERROR: Invalid JSON in config file${nc}" >&2
        return 1
    fi
    
    local users=()
    
    # Extract VMess WS users - FIXED: handle empty clients array
    if jq -e '.inbounds[] | select(.tag == "vmess-ws") | .settings.clients' "$config_file" > /dev/null 2>&1; then
        local ws_users=$(jq -r '.inbounds[] | select(.tag == "vmess-ws") | .settings.clients[]? | .email // empty' "$config_file" 2>/dev/null)
        if [[ -n "$ws_users" ]]; then
            while IFS= read -r user; do
                [[ -n "$user" ]] && users+=("$user")
            done <<< "$ws_users"
        fi
    fi
    
    # Extract VMess gRPC users - FIXED: handle empty clients array
    if jq -e '.inbounds[] | select(.tag == "vmess-grpc") | .settings.clients' "$config_file" > /dev/null 2>&1; then
        local grpc_users=$(jq -r '.inbounds[] | select(.tag == "vmess-grpc") | .settings.clients[]? | .email // empty' "$config_file" 2>/dev/null)
        if [[ -n "$grpc_users" ]]; then
            while IFS= read -r user; do
                [[ -n "$user" ]] && users+=("$user")
            done <<< "$grpc_users"
        fi
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${users[@]}" | sort -u
}

# Function to validate username - FIXED
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
    
    # Check if username already exists using jq - FIXED METHOD
    if command -v jq &> /dev/null; then
        # Check in VMess WS
        local user_exists_ws=$(jq '.inbounds[] | select(.tag == "vmess-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .email' /usr/local/etc/xray/config.json 2>/dev/null)
        # Check in VMess gRPC
        local user_exists_grpc=$(jq '.inbounds[] | select(.tag == "vmess-grpc") | .settings.clients[]? | select(.email == "'"$user"'") | .email' /usr/local/etc/xray/config.json 2>/dev/null)
        
        if [[ -n "$user_exists_ws" ]] || [[ -n "$user_exists_grpc" ]]; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    else
        # Fallback to grep
        local user_exists=$(grep -o "\"email\":\"$user\"" /usr/local/etc/xray/config.json 2>/dev/null | wc -l)
        if [[ $user_exists -gt 0 ]]; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    fi
    
    return 0
}

# Function to backup config
backup_config() {
    local config_file="/usr/local/etc/xray/config.json"
    local backup_file="/usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S)"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found for backup${nc}" >&2
        return 1
    fi
    
    if cp "$config_file" "$backup_file" 2>/dev/null; then
        echo "$backup_file"
        return 0
    else
        echo -e "${red}ERROR: Failed to create backup${nc}" >&2
        return 1
    fi
}

# Function to restore config on error
restore_config() {
    local backup_file="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ -f "$backup_file" ]]; then
        if cp "$backup_file" "$config_file"; then
            echo -e "${green}✓ Config restored from backup${nc}"
            rm -f "$backup_file" 2>/dev/null
            return 0
        else
            echo -e "${red}✗ Failed to restore config from backup${nc}"
            return 1
        fi
    else
        echo -e "${red}✗ Backup file not found: $backup_file${nc}"
        return 1
    fi
}

# Function to add user using jq - FIXED
add_vmess_user() {
    local user="$1"
    local uuid="$2"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        echo -e "${yellow}Installing jq...${nc}"
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo -e "${red}ERROR: Failed to install jq${nc}" >&2
            return 1
        fi
    fi
    
    # Backup config
    local backup_file=$(backup_config)
    if [[ -z "$backup_file" ]]; then
        echo -e "${red}ERROR: Failed to create backup${nc}" >&2
        return 1
    fi
    
    echo -e "${yellow}Backup created: $backup_file${nc}"
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR${nc}: Config file not found: $config_file"
        restore_config "$backup_file"
        return 1
    fi
    
    # Validate JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Invalid JSON in config file"
        restore_config "$backup_file"
        return 1
    fi
    
    # Get current client count
    current_ws_clients=$(jq '[.inbounds[] | select(.tag == "vmess-ws") | .settings.clients[]?] | length' "$config_file")
    echo -e "${yellow}Current VMess WS clients: $current_ws_clients${nc}"
    
    # Add to VMess WS - FIXED: better error handling
    echo -e "${yellow}Adding user to VMess WS...${nc}"
    if ! jq '(.inbounds[] | select(.tag == "vmess-ws").settings.clients) += [{"id": "'"$uuid"'", "alterId": 0, "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Failed to update VMess WS config (jq error)"
        restore_config "$backup_file"
        return 1
    fi
    
    if [[ ! -f "${config_file}.tmp" ]]; then
        echo -e "${red}ERROR${nc}: Temporary file not created"
        restore_config "$backup_file"
        return 1
    fi
    
    # Validate the temp file before replacing
    if ! jq empty "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Generated config has invalid JSON"
        rm -f "${config_file}.tmp"
        restore_config "$backup_file"
        return 1
    fi
    
    mv "${config_file}.tmp" "$config_file"
    echo -e "${green}✓ User added to VMess WS${nc}"
    
    # Add to VMess gRPC if exists
    if jq -e '.inbounds[] | select(.tag == "vmess-grpc")' "$config_file" > /dev/null 2>&1; then
        echo -e "${yellow}Adding user to VMess gRPC...${nc}"
        if jq '(.inbounds[] | select(.tag == "vmess-grpc").settings.clients) += [{"id": "'"$uuid"'", "alterId": 0, "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp2" 2>/dev/null; then
            if jq empty "${config_file}.tmp2" 2>/dev/null; then
                mv "${config_file}.tmp2" "$config_file"
                echo -e "${green}✓ User added to VMess gRPC${nc}"
            else
                echo -e "${yellow}⚠ Invalid JSON generated for gRPC update, skipping${nc}"
                rm -f "${config_file}.tmp2"
            fi
        else
            echo -e "${yellow}⚠ Failed to update VMess gRPC${nc}"
        fi
    fi
    
    # Verify the user was added to WS
    local user_added_ws=$(jq '.inbounds[] | select(.tag == "vmess-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
    
    if [[ "$user_added_ws" == "\"$user\"" ]]; then
        echo -e "${green}✓ User successfully verified in VMess WS${nc}"
        
        # Update expiry database
        update_user_expiry "$user" "$exp"
        
        # Clean up backup file on success
        rm -f "$backup_file" 2>/dev/null
        
        # Show new client count
        new_ws_clients=$(jq '[.inbounds[] | select(.tag == "vmess-ws") | .settings.clients[]?] | length' "$config_file")
        echo -e "${yellow}New VMess WS clients: $new_ws_clients${nc}"
        
        return 0
    else
        echo -e "${red}ERROR${nc}: User not found in VMess WS after update"
        restore_config "$backup_file"
        return 1
    fi
}

# Function to update user expiry - NEW
update_user_expiry() {
    local user="$1"
    local new_exp="$2"
    local expiry_files=(
        "/etc/xray/user_expiry.txt"
        "/root/user_expiry.txt"
        "/usr/local/etc/xray/user_expiry.txt"
    )
    
    # Try to update existing expiry file
    for file in "${expiry_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Remove existing entry
            sed -i "/^$user /d" "$file" 2>/dev/null
            # Add new entry
            echo "$user $new_exp" >> "$file"
            echo -e "${green}✓ Expiry set in database: $new_exp${nc}"
            return 0
        fi
    done
    
    # If no expiry file exists, create one
    local expiry_file="/etc/xray/user_expiry.txt"
    mkdir -p "$(dirname "$expiry_file")"
    echo "$user $new_exp" >> "$expiry_file"
    echo -e "${green}✓ Created new expiry file: $(basename "$expiry_file")${nc}"
    return 0
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}           ADD VMESS ACCOUNT           ${nc}"
echo -e "${red}=========================================${nc}"

# Validate domain exists
if [[ -z "$domain" ]] || [[ "$domain" == "unknown" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"
none="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess WS none TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"
grpc_port="$(cat ~/log-install.txt 2>/dev/null | grep -w "Vmess gRPC" | cut -d: -f2 | sed 's/ //g' | head -1)"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$none" ]]; then
    echo -e "${red}ERROR${nc}: Could not find VMess ports in log file."
    echo -e "${yellow}Please check if VMess is properly installed.${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Check if gRPC is available
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
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           ADD VMESS ACCOUNT           ${nc}"
    echo -e "${red}=========================================${nc}"
done

# Generate UUID
uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || openssl rand -hex 16 2>/dev/null || echo "fallback-$(date +%s)")

if [[ -z "$uuid" ]]; then
    echo -e "${red}ERROR${nc}: Failed to generate UUID"
    exit 1
fi

# Get expiry date with validation
while true; do
    echo ""
    read -p "Expired (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [[ $masaaktif -gt 0 ]]; then
        if [[ $masaaktif -gt 3650 ]]; then
            echo -e "${red}ERROR${nc}: Cannot extend more than 10 years"
            continue
        fi
        break
    else
        echo -e "${red}ERROR${nc}: Please enter a valid number of days"
    fi
done

exp=$(date -d "$masaaktif days" +"%Y-%m-%d" 2>/dev/null || date -v+"$masaaktif"d "+%Y-%m-%d" 2>/dev/null || echo "unknown")
echo -e "${yellow}Account will expire on: $exp${nc}"

# Add user to config
echo -e "${yellow}Updating Xray configuration...${nc}"
if ! add_vmess_user "$user" "$uuid"; then
    echo -e "${red}ERROR${nc}: Failed to update config.json"
    echo -e "${yellow}Restoring backup...${nc}"
    latest_backup=$(ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        cp "$latest_backup" /usr/local/etc/xray/config.json
        echo -e "${green}✓ Config restored from backup${nc}"
    fi
    exit 1
fi

# Create VMess JSON configurations
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

# Create VMess links
vmesslink1="vmess://$(echo "$wstls" | base64 -w 0 2>/dev/null || echo "$wstls" | base64 2>/dev/null || echo "base64_error")"
vmesslink2="vmess://$(echo "$wsnontls" | base64 -w 0 2>/dev/null || echo "$wsnontls" | base64 2>/dev/null || echo "base64_error")"

# Create gRPC link if available
if $grpc_enabled; then
    grpc=$(cat<<EOF
{
  "v": "2",
  "ps": "${user}-gRPC",
  "add": "${domain}",
  "port": "${grpc_port}",
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
    vmesslink3="vmess://$(echo "$grpc" | base64 -w 0 2>/dev/null || echo "$grpc" | base64 2>/dev/null || echo "base64_error")"
fi

# Restart Xray service
echo -e "${yellow}Restarting Xray service...${nc}"
if systemctl restart xray; then
    echo -e "${green}✓ Xray service restarted successfully${nc}"
    
    # Wait and check if service is running
    sleep 3
    if systemctl is-active --quiet xray; then
        echo -e "${green}✓ Xray service is running properly${nc}"
        
        # Test config
        if /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
            echo -e "${green}✓ Xray config test passed${nc}"
        else
            echo -e "${red}✗ Xray config test failed${nc}"
        fi
        
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

# VMess WS TLS (Recommended)
${vmesslink1}

# VMess WS None TLS  
${vmesslink2}

END

        # Add gRPC section if enabled
        if $grpc_enabled; then
            cat >> "$CLIENT_DIR/vmess-$user.txt" <<-END
# VMess gRPC
${vmesslink3}

END
        fi

        cat >> "$CLIENT_DIR/vmess-$user.txt" <<-END
# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $none
END

        if $grpc_enabled; then
            cat >> "$CLIENT_DIR/vmess-$user.txt" <<-END
- Port gRPC: $grpc_port
END
        fi

        cat >> "$CLIENT_DIR/vmess-$user.txt" <<-END
- UUID: $uuid
- Alter ID: 0
- Security: auto
- Network: WebSocket
- Path: /vmess
- Expiry: $exp

# For V2RayN / V2RayNG:
- Address: $domain
- Port: $tls (TLS) / $none (None TLS)
- UUID: $uuid
- Alter ID: 0
- Security: auto
- Transport: WebSocket
- Path: /vmess
- Host: $domain

END

        if $grpc_enabled; then
            cat >> "$CLIENT_DIR/vmess-$user.txt" <<-END
# For gRPC Clients:
- Address: $domain
- Port: $grpc_port
- UUID: $uuid
- Alter ID: 0
- Security: auto
- Transport: gRPC
- Service Name: vmess-grpc
- Host: $domain

END
        fi

        # Display results
        clear
        echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        echo -e "${blue}           VMESS ACCOUNT CREATED       ${nc}" | tee -a /var/log/create-vmess.log
        echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        echo -e "Remarks        : ${user}" | tee -a /var/log/create-vmess.log
        echo -e "IP             : ${MYIP}" | tee -a /var/log/create-vmess.log
        echo -e "Domain         : ${domain}" | tee -a /var/log/create-vmess.log
        echo -e "Port TLS       : ${tls}" | tee -a /var/log/create-vmess.log
        echo -e "Port none TLS  : ${none}" | tee -a /var/log/create-vmess.log
        if $grpc_enabled; then
            echo -e "Port gRPC      : ${grpc_port}" | tee -a /var/log/create-vmess.log
        fi
        echo -e "UUID           : ${uuid}" | tee -a /var/log/create-vmess.log
        echo -e "Alter ID       : 0" | tee -a /var/log/create-vmess.log
        echo -e "Security       : auto" | tee -a /var/log/create-vmess.log
        echo -e "Network        : WebSocket" | tee -a /var/log/create-vmess.log
        echo -e "Path           : /vmess" | tee -a /var/log/create-vmess.log
        echo -e "Expired On     : $exp" | tee -a /var/log/create-vmess.log
        echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        echo -e "${green}VMess WS TLS${nc}" | tee -a /var/log/create-vmess.log
        echo -e "${vmesslink1}" | tee -a /var/log/create-vmess.log
        echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        echo -e "${green}VMess WS None TLS${nc}" | tee -a /var/log/create-vmess.log
        echo -e "${vmesslink2}" | tee -a /var/log/create-vmess.log
        echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        if $grpc_enabled; then
            echo -e "${green}VMess gRPC${nc}" | tee -a /var/log/create-vmess.log
            echo -e "${vmesslink3}" | tee -a /var/log/create-vmess.log
            echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        fi
        echo -e "Config File    : $CLIENT_DIR/vmess-$user.txt" | tee -a /var/log/create-vmess.log
        echo -e "${red}=========================================${nc}" | tee -a /var/log/create-vmess.log
        echo "" | tee -a /var/log/create-vmess.log
        
        # Log the creation
        echo "$(date): Created VMess account '$user' (UUID: $uuid, exp: $exp)" >> /var/log/create-vmess.log 2>/dev/null
        
        echo -e "${green}SUCCESS${nc}: VMess account $user created successfully!"
        
    else
        echo -e "${red}✗ Xray service failed to start${nc}"
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

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess 2>/dev/null || exit 0
