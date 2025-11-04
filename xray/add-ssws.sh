#!/bin/bash
# =========================================
# Add Shadowsocks Account - FIXED VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

# ==========================================
# Getting system info
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# Validate domain exists
if [[ -z "$domain" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS TLS" | cut -d: -f2 | sed 's/ //g')"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS none TLS" | cut -d: -f2 | sed 's/ //g')"
grpc_port="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks gRPC" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Shadowsocks ports in log file."
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
        # Check in Shadowsocks WS
        local user_exists_ws=$(jq '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .email' /usr/local/etc/xray/config.json 2>/dev/null)
        # Check in Shadowsocks gRPC
        local user_exists_grpc=$(jq '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]? | select(.email == "'"$user"'") | .email' /usr/local/etc/xray/config.json 2>/dev/null)
        
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

# Function to check if ss-grpc inbound exists - NEW
check_ss_grpc_exists() {
    local config_file="$1"
    if jq '.inbounds[] | select(.tag == "ss-grpc")' "$config_file" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to add user using jq - FIXED
add_shadowsocks_user() {
    local user="$1"
    local uuid="$2"
    local cipher="$3"
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
    current_ws_clients=$(jq '[.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]?] | length' "$config_file")
    echo -e "${yellow}Current Shadowsocks WS clients: $current_ws_clients${nc}"
    
    # Add to Shadowsocks WS - FIXED: better error handling
    echo -e "${yellow}Adding user to Shadowsocks WS...${nc}"
    if ! jq '(.inbounds[] | select(.tag == "ss-ws").settings.clients) += [{"password": "'"$uuid"'", "method": "'"$cipher"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Failed to update Shadowsocks WS config (jq error)"
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
    echo -e "${green}✓ User added to Shadowsocks WS${nc}"
    
    # Add to Shadowsocks gRPC if enabled AND exists - FIXED CHECK
    if $grpc_enabled && check_ss_grpc_exists "$config_file"; then
        echo -e "${yellow}Adding user to Shadowsocks gRPC...${nc}"
        if jq '(.inbounds[] | select(.tag == "ss-grpc").settings.clients) += [{"password": "'"$uuid"'", "method": "'"$cipher"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp2" 2>/dev/null; then
            if jq empty "${config_file}.tmp2" 2>/dev/null; then
                mv "${config_file}.tmp2" "$config_file"
                echo -e "${green}✓ User added to Shadowsocks gRPC${nc}"
            else
                echo -e "${yellow}⚠ Invalid JSON generated for gRPC update, skipping${nc}"
                rm -f "${config_file}.tmp2"
            fi
        else
            echo -e "${yellow}⚠ Failed to update Shadowsocks gRPC${nc}"
        fi
    elif $grpc_enabled; then
        echo -e "${yellow}⚠ Shadowsocks gRPC tag not found in config, skipping${nc}"
    fi
    
    # Verify the user was added to WS
    local user_added_ws=$(jq '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
    
    if [[ "$user_added_ws" == "\"$user\"" ]]; then
        echo -e "${green}✓ User successfully verified in Shadowsocks WS${nc}"
    else
        echo -e "${red}ERROR${nc}: User not found in Shadowsocks WS after update"
        restore_config "$backup_file"
        return 1
    fi
    
    # Verify the user was added to gRPC if exists
    if $grpc_enabled && check_ss_grpc_exists "$config_file"; then
        local user_added_grpc=$(jq '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]? | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
        if [[ "$user_added_grpc" == "\"$user\"" ]]; then
            echo -e "${green}✓ User successfully verified in Shadowsocks gRPC${nc}"
        else
            echo -e "${yellow}⚠ User not found in Shadowsocks gRPC after update${nc}"
        fi
    fi
    
    # Show final counts
    new_ws_clients=$(jq '[.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]?] | length' "$config_file")
    echo -e "${yellow}New Shadowsocks WS clients: $new_ws_clients${nc}"
    
    if $grpc_enabled && check_ss_grpc_exists "$config_file"; then
        new_grpc_clients=$(jq '[.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]?] | length' "$config_file")
        echo -e "${yellow}New Shadowsocks gRPC clients: $new_grpc_clients${nc}"
    fi
    
    # Clean up backup file on success
    rm -f "$backup_file" 2>/dev/null
    
    return 0
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

# Main user input loop
while true; do
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}        ADD SHADOWSOCKS ACCOUNT        ${nc}"
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

# Cipher and UUID
cipher="aes-128-gcm"
uuid=$(cat /proc/sys/kernel/random/uuid)

# Get expiry date with validation
while true; do
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

exp=$(date -d "$masaaktif days" +"%Y-%m-%d")
echo -e "${yellow}Account will expire on: $exp${nc}"

# Add user to config
echo -e "${yellow}Updating Xray configuration...${nc}"
if ! add_shadowsocks_user "$user" "$uuid" "$cipher"; then
    echo -e "${red}ERROR${nc}: Failed to update config.json"
    echo -e "${yellow}Restoring backup...${nc}"
    latest_backup=$(ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        cp "$latest_backup" /usr/local/etc/xray/config.json
        echo -e "${green}✓ Config restored from backup${nc}"
    fi
    exit 1
fi

# Update expiry database
echo -e "${yellow}Setting expiry date...${nc}"
update_user_expiry "$user" "$exp"

# Create Shadowsocks links
ss_ws_tls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${tls}?plugin=v2ray-plugin%3Bpath%3D%2Fss-ws%3Bhost%3D${domain}%3Btls#${user}"
ss_ws_ntls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${ntls}?plugin=v2ray-plugin%3Bpath%3D%2Fss-ws%3Bhost%3D${domain}#${user}"

# Create gRPC link if enabled
if $grpc_enabled; then
    ss_grpc="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${grpc_port}?plugin=grpc%3BserviceName%3Dss-grpc%3Btls#${user}-gRPC"
fi

# Standard Shadowsocks links (without plugin)
shadowsockslink="ss://$(echo -n "${cipher}:${uuid}@${domain}:${tls}" | base64 -w 0)#${user}-TLS"
shadowsockslink2="ss://$(echo -n "${cipher}:${uuid}@${domain}:${ntls}" | base64 -w 0)#${user}-NoTLS"

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

# Create client config file
CLIENT_DIR="/home/vps/public_html"
mkdir -p "$CLIENT_DIR"

cat > "$CLIENT_DIR/ss-$user.txt" <<-END
# ==========================================
# Shadowsocks Client Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp
# ==========================================

# Basic Shadowsocks Configuration:
- Server: $domain
- Port (TLS): $tls
- Port (Non-TLS): $ntls
END

if $grpc_enabled; then
cat >> "$CLIENT_DIR/ss-$user.txt" <<-END
- Port gRPC: $grpc_port
END
fi

cat >> "$CLIENT_DIR/ss-$user.txt" <<-END
- Password: $uuid
- Method: $cipher
- Protocol: Shadowsocks
- Expiry: $exp

# Quick Connect Links:

# Shadowsocks WS TLS (Recommended)
${ss_ws_tls}

# Shadowsocks WS None TLS
${ss_ws_ntls}

END

if $grpc_enabled; then
cat >> "$CLIENT_DIR/ss-$user.txt" <<-END
# Shadowsocks gRPC
${ss_grpc}

END
fi

cat >> "$CLIENT_DIR/ss-$user.txt" <<-END
# Standard Shadowsocks (Raw - may not work with WebSocket):
${shadowsockslink}

# Configuration Details:

# WebSocket Configuration:
- Transport: WebSocket
- WebSocket Path: /ss-ws
- TLS Host: $domain

END

if $grpc_enabled; then
cat >> "$CLIENT_DIR/ss-$user.txt" <<-END
# gRPC Configuration:
- Transport: gRPC
- Service Name: ss-grpc
- TLS: Enabled

END
fi

cat >> "$CLIENT_DIR/ss-$user.txt" <<-END
# For Shadowsocks Clients with v2ray-plugin:
- Install v2ray-plugin for your Shadowsocks client
- Use standard Shadowsocks config with plugin: v2ray-plugin
- Plugin options: 
  TLS: path=/ss-ws;host=$domain;tls
  Non-TLS: path=/ss-ws;host=$domain

# For Android (Shadowrocket/Sagernet):
- Type: Shadowsocks
- Server: $domain
- Port: $tls (TLS) / $ntls (Non-TLS)
- Password: $uuid
- Algorithm: $cipher
- Plugin: v2ray-plugin
- Plugin Options: 
  TLS: path=/ss-ws;host=$domain;tls
  Non-TLS: path=/ss-ws;host=$domain

# NOTE: This configuration uses WebSocket transport
# Standard Shadowsocks without plugin may not work

END

# Display results
clear
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${blue}        SHADOWSOCKS ACCOUNT CREATED     ${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Remarks        : ${user}" | tee -a /var/log/create-shadowsocks.log
echo -e "IP             : ${MYIP}" | tee -a /var/log/create-shadowsocks.log
echo -e "Domain         : ${domain}" | tee -a /var/log/create-shadowsocks.log
echo -e "Port TLS       : ${tls}" | tee -a /var/log/create-shadowsocks.log
echo -e "Port none TLS  : ${ntls}" | tee -a /var/log/create-shadowsocks.log
if $grpc_enabled; then
echo -e "Port gRPC      : ${grpc_port}" | tee -a /var/log/create-shadowsocks.log
fi
echo -e "Password       : ${uuid}" | tee -a /var/log/create-shadowsocks.log
echo -e "Cipher         : ${cipher}" | tee -a /var/log/create-shadowsocks.log
echo -e "Expired On     : $exp" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${green}Shadowsocks WS TLS (Recommended)${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${ss_ws_tls}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${green}Shadowsocks WS None TLS${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${ss_ws_ntls}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
if $grpc_enabled; then
echo -e "${green}Shadowsocks gRPC${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${ss_grpc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
fi
echo -e "${green}Standard Shadowsocks (Raw)${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${shadowsockslink}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Config File    : $CLIENT_DIR/ss-$user.txt" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo "" | tee -a /var/log/create-shadowsocks.log

# Clean up old backups (keep last 5)
ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | tail -n +6 | xargs -r rm

echo -e "${green}SUCCESS${nc}: Shadowsocks account $user created successfully!"

read -n 1 -s -r -p "Press any key to back on menu"
m-ssws
