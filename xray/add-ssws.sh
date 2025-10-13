#!/bin/bash
# =========================================
# Add Shadowsocks Account - IMPROVED VERSION
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

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Shadowsocks ports in log file."
    exit 1
fi

# Function to validate username
validate_username() {
    local user="$1"
    if [[ ! $user =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}ERROR${nc}: Username can only contain letters, numbers and underscores"
        return 1
    fi
    
    # Check if user exists using jq (more reliable)
    if command -v jq &> /dev/null; then
        local user_exists=$(jq '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[] | select(.email == "'"$user"'")' /usr/local/etc/xray/config.json 2>/dev/null | wc -l)
        if [[ $user_exists -gt 0 ]]; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    else
        # Fallback to grep
        local user_exists=$(grep -w "$user" /usr/local/etc/xray/config.json 2>/dev/null | wc -l)
        if [[ $user_exists -gt 0 ]]; then
            echo -e "${red}ERROR${nc}: User $user already exists"
            return 1
        fi
    fi
    
    return 0
}

# Function to add user using jq
add_shadowsocks_user() {
    local user="$1"
    local uuid="$2"
    local cipher="$3"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        echo -e "${yellow}Installing jq...${nc}"
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
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
    
    echo -e "${yellow}Current Shadowsocks WS clients: $(jq '[.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]] | length' "$config_file")${nc}"
    
    # Add to Shadowsocks WS
    echo -e "${yellow}Adding user to Shadowsocks WS...${nc}"
    jq '(.inbounds[] | select(.tag == "ss-ws").settings.clients) += [{"password": "'"$uuid"'", "method": "'"$cipher"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp"
    
    if [[ $? -ne 0 ]] || [[ ! -f "${config_file}.tmp" ]]; then
        echo -e "${red}ERROR${nc}: Failed to update Shadowsocks WS"
        return 1
    fi
    
    mv "${config_file}.tmp" "$config_file"
    
    # Add to Shadowsocks gRPC if exists
    if jq -e '.inbounds[] | select(.tag == "ss-grpc")' "$config_file" > /dev/null 2>&1; then
        echo -e "${yellow}Adding user to Shadowsocks gRPC...${nc}"
        jq '(.inbounds[] | select(.tag == "ss-grpc").settings.clients) += [{"password": "'"$uuid"'", "method": "'"$cipher"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp"
        
        if [[ $? -eq 0 ]] && [[ -f "${config_file}.tmp" ]]; then
            mv "${config_file}.tmp" "$config_file"
            echo -e "${green}✓ User added to Shadowsocks gRPC${nc}"
        else
            echo -e "${yellow}⚠ Failed to add to Shadowsocks gRPC (may not exist)${nc}"
        fi
    fi
    
    # Verify the user was added
    local user_added=$(jq '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[] | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
    
    if [[ "$user_added" == "\"$user\"" ]]; then
        echo -e "${green}✓ User successfully added to Shadowsocks WS${nc}"
        echo -e "${yellow}New Shadowsocks WS clients: $(jq '[.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]] | length' "$config_file")${nc}"
        
        # Add comment for expiry tracking
        sed -i "/\"clients\": \[/a #! $user $exp" "$config_file" 2>/dev/null
        
        # Clean up backup file on success
        rm -f "$backup_file" 2>/dev/null
        return 0
    else
        echo -e "${red}ERROR${nc}: User not found in config after update"
        restore_config "$backup_file"
        return 1
    fi
}

# Function to restore config on error
restore_config() {
    local backup_file="$1"
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "/usr/local/etc/xray/config.json"
        rm -f "$backup_file"
        echo -e "${green}✓ Config restored from backup${nc}"
    fi
}

# Function to generate base64 Shadowsocks URL
generate_ss_url() {
    local cipher="$1"
    local uuid="$2"
    local domain="$3"
    local port="$4"
    local path="$5"
    local security="$6"
    local user="$7"
    
    # Format: ss://method:password@host:port#remark
    local ss_string="${cipher}:${uuid}@${domain}:${port}"
    local encoded=$(echo -n "$ss_string" | base64 -w 0)
    
    if [[ "$security" == "tls" ]]; then
        echo "ss://${encoded}?plugin=v2ray-plugin%3Bpath%3D%2F${path}%3Bhost%3D${domain}%3Btls#${user}"
    else
        echo "ss://${encoded}?plugin=v2ray-plugin%3Bpath%3D%2F${path}%3Bhost%3D${domain}#${user}"
    fi
}

# Main user input loop
while true; do
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}        ADD SHADOWSOCKS ACCOUNT        ${nc}"
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

# Cipher and UUID
cipher="aes-128-gcm"
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

# Create Shadowsocks links
shadowsockslink="ss://$(echo -n "${cipher}:${uuid}@${domain}:${tls}" | base64 -w 0)#${user}"
shadowsockslink1="ss://$(echo -n "${cipher}:${uuid}@${domain}:${ntls}" | base64 -w 0)#${user}"

# Alternative links with v2ray-plugin format
ss_ws_tls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${tls}?plugin=v2ray-plugin%3Bpath%3D%2Fss-ws%3Bhost%3D${domain}%3Btls#${user}"
ss_ws_ntls="ss://$(echo -n "${cipher}:${uuid}" | base64 -w 0)@${domain}:${ntls}?plugin=v2ray-plugin%3Bpath%3D%2Fss-ws%3Bhost%3D${domain}#${user}"

# Restart Xray service
echo -e "${yellow}Restarting Xray service...${nc}"
if systemctl restart xray; then
    echo -e "${green}✓ Xray service restarted successfully${nc}"
    
    # Wait and check if service is running
    sleep 2
    if systemctl is-active --quiet xray; then
        echo -e "${green}✓ Xray service is running properly${nc}"
    else
        echo -e "${red}✗ Xray service failed to start${nc}"
        echo -e "${yellow}Restoring backup config...${nc}"
        latest_backup=$(ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" /usr/local/etc/xray/config.json
            systemctl restart xray
        fi
        exit 1
    fi
else
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
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
- Password: $uuid
- Method: $cipher
- Protocol: Shadowsocks
- Transport: WebSocket
- Path: /ss-ws

# Quick Connect Links:

# Shadowsocks WS TLS
${ss_ws_tls}

# Shadowsocks WS None TLS
${ss_ws_ntls}

# Standard Shadowsocks (Raw):
${shadowsockslink}

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

# Expiry: $exp

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
echo -e "Password       : ${uuid}" | tee -a /var/log/create-shadowsocks.log
echo -e "Cipher         : ${cipher}" | tee -a /var/log/create-shadowsocks.log
echo -e "Network        : WebSocket" | tee -a /var/log/create-shadowsocks.log
echo -e "Path           : /ss-ws" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${green}Shadowsocks WS TLS${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${ss_ws_tls}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${green}Shadowsocks WS None TLS${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${ss_ws_ntls}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${green}Standard Shadowsocks${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${shadowsockslink}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Expired On     : $exp" | tee -a /var/log/create-shadowsocks.log
echo -e "Config File    : $CLIENT_DIR/ss-$user.txt" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo "" | tee -a /var/log/create-shadowsocks.log

# Clean up old backups (keep last 5)
ls -t /usr/local/etc/xray/config.json.backup.* 2>/dev/null | tail -n +6 | xargs -r rm

echo -e "${green}SUCCESS${nc}: Shadowsocks account $user created successfully!"

read -n 1 -s -r -p "Press any key to back on menu"
m-ssws
