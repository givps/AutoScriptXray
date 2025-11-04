#!/bin/bash
# ==========================================
# Create Trial Trojan Account - FIXED VERSION
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
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan WS TLS" | cut -d: -f2 | sed 's/ //g')"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Trojan WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Trojan ports in log file."
    exit 1
fi

# Function to generate random username - IMPROVED
generate_trial_username() {
    local prefix="trial"
    # Generate more random characters
    local random_chars=$(head /dev/urandom | tr -dc A-Z0-9 | head -c8)
    echo "${prefix}-${random_chars}"
}

# Function to check if username already exists - FIXED
username_exists() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        # Check both Trojan WS and gRPC
        jq '.inbounds[] | select(.tag == "trojan-ws" or .tag == "trojan-grpc") | .settings.clients[]? | select(.email == "'"$user"'")' "$config_file" 2>/dev/null | grep -q .
    else
        grep -q "\"email\": \"$user\"" "$config_file" 2>/dev/null
    fi
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
        echo -e "${red}✗ Backup file not found${nc}"
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
    current_clients=$(jq '[.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]?] | length' "$config_file")
    echo -e "${yellow}Current Trojan WS clients: $current_clients${nc}"
    
    # Add to Trojan WS - FIXED: better error handling
    echo -e "${yellow}Adding trial user to Trojan WS...${nc}"
    if ! jq '(.inbounds[] | select(.tag == "trojan-ws").settings.clients) += [{"password": "'"$uuid"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR${nc}: Failed to update Trojan WS config (jq error)"
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
    
    # Verify the user was added
    local user_added=$(jq '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
    
    if [[ "$user_added" == "\"$user\"" ]]; then
        echo -e "${green}✓ Trial user successfully added to Trojan WS${nc}"
        
        # Update expiry database
        update_user_expiry "$user" "$exp"
        
        # Clean up backup file on success
        rm -f "$backup_file" 2>/dev/null
        
        # Show new client count
        new_clients=$(jq '[.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]?] | length' "$config_file")
        echo -e "${yellow}New Trojan WS clients: $new_clients${nc}"
        
        return 0
    else
        echo -e "${red}ERROR${nc}: Trial user not found in config after update"
        restore_config "$backup_file"
        return 1
    fi
}

# Function to update user expiry - NEW
update_user_expiry() {
    local user="$1"
    local new_exp="$2"
    local expiry_file="/etc/xray/user_expiry.txt"
    
    # Create directory if not exists
    mkdir -p "$(dirname "$expiry_file")"
    
    # Remove existing entry if any
    if [[ -f "$expiry_file" ]]; then
        sed -i "/^$user /d" "$expiry_file" 2>/dev/null
    fi
    
    # Add new entry
    echo "$user $new_exp" >> "$expiry_file"
    echo -e "${green}✓ Expiry set in database: $new_exp${nc}"
}

# Function to get current trial count - NEW
get_trial_count() {
    local expiry_file="/etc/xray/user_expiry.txt"
    local today=$(date +%Y-%m-%d)
    local count=0
    
    if [[ -f "$expiry_file" ]]; then
        while IFS= read -r line; do
            local trial_user=$(echo "$line" | awk '{print $1}')
            local trial_expiry=$(echo "$line" | awk '{print $2}')
            
            # Check if it's a trial user and not expired
            if [[ "$trial_user" == trial-* ]] && [[ "$trial_expiry" > "$today" ]]; then
                ((count++))
            fi
        done < "$expiry_file"
    fi
    
    echo $count
}

# Display header
echo -e "${red}=========================================${nc}"
echo -e "${blue}         CREATE TROJAN TRIAL          ${nc}"
echo -e "${red}=========================================${nc}"

# Check current trial count
current_trials=$(get_trial_count)
echo -e "${yellow}Active trials: $current_trials${nc}"
echo ""

# Generate unique trial user
max_attempts=10
attempt=1
while [[ $attempt -le $max_attempts ]]; do
    user=$(generate_trial_username)
    if ! username_exists "$user"; then
        break
    fi
    echo -e "${yellow}Username $user exists, generating new one... (attempt $attempt/$max_attempts)${nc}"
    ((attempt++))
    sleep 1
done

if [[ $attempt -gt $max_attempts ]]; then
    echo -e "${red}ERROR${nc}: Failed to generate unique username after $max_attempts attempts"
    echo -e "${yellow}Too many trial users exist, please clean up first${nc}"
    exit 1
fi

# Generate UUID and set trial period
uuid=$(cat /proc/sys/kernel/random/uuid)
masaaktif=1
exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

echo -e "${green}Generated trial account:${nc}"
echo -e "  Username : $user"
echo -e "  Password : $uuid"
echo -e "  Expiry   : $exp (1 day trial)"
echo ""

# Add user to config
echo -e "${yellow}Configuring trial account...${nc}"
if add_trojan_user "$user" "$uuid"; then
    # Create Trojan links dengan path yang benar: /trojan-ws
    trojanlink="trojan://${uuid}@${domain}:${tls}?path=%2Ftrojan-ws&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
    trojanlink2="trojan://${uuid}@${domain}:${ntls}?path=%2Ftrojan-ws&security=none&host=${domain}&type=ws#${user}"
    
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray; then
        echo -e "${green}✓ Xray service restarted successfully${nc}"
        
        # Wait a moment for service to stabilize
        sleep 2
        
        # Check if Xray is running
        if systemctl is-active --quiet xray; then
            echo -e "${green}✓ Xray service is running properly${nc}"
            
            # Create client config file
            CLIENT_DIR="/home/vps/public_html"
            mkdir -p "$CLIENT_DIR"
            
            cat > "$CLIENT_DIR/trojan-$user.txt" <<-END
# ==========================================
# Trojan Trial Configuration
# Generated: $(date)
# Username: $user
# Type: 1-Day Trial Account
# Expiry: $exp
# ==========================================

# IMPORTANT: This is a TRIAL account
# Will expire automatically in 24 hours

# Trojan WS TLS (Recommended)
${trojanlink}

# Trojan WS None TLS
${trojanlink2}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $ntls
- Password: $uuid
- Path: /trojan-ws
- Transport: WebSocket
- Expiry: $exp (1 day trial)

# For V2RayN / V2RayNG:
- Address: $domain
- Port: $tls (TLS) / $ntls (None TLS)
- Password: $uuid
- Transport: WebSocket
- Path: /trojan-ws
- Host: $domain

# For Shadowrocket:
- Type: Trojan
- Server: $domain
- Port: $tls
- Password: $uuid
- SNI: $domain
- Transport: WebSocket
- WebSocket Path: /trojan-ws

END

            # Display results
            clear
            echo -e "${red}=========================================${nc}"
            echo -e "${blue}         TROJAN TRIAL CREATED         ${nc}"
            echo -e "${red}=========================================${nc}"
            echo -e "Remarks        : ${user} ${yellow}(TRIAL)${nc}"
            echo -e "IP             : ${MYIP}"
            echo -e "Domain         : ${domain}"
            echo -e "Port TLS       : ${tls}"
            echo -e "Port none TLS  : ${ntls}"
            echo -e "Password       : ${uuid}"
            echo -e "Network        : WebSocket"
            echo -e "Path           : /trojan-ws"
            echo -e "Expired On     : $exp ${yellow}(1 day trial)${nc}"
            echo -e "${red}=========================================${nc}"
            echo -e "${green}Link TLS (WS) - RECOMMENDED${nc}"
            echo -e "${trojanlink}"
            echo -e "${red}=========================================${nc}"
            echo -e "${green}Link none TLS (WS)${nc}"
            echo -e "${trojanlink2}"
            echo -e "${red}=========================================${nc}"
            echo -e "Config File    : $CLIENT_DIR/trojan-$user.txt"
            echo -e "${red}=========================================${nc}"
            echo ""
            
            # Log the creation
            echo "$(date): Created trial Trojan account '$user' (exp: $exp)" >> /var/log/trial-trojan.log
            
            echo -e "${green}✅ TRIAL ACCOUNT CREATED SUCCESSFULLY${nc}"
            echo -e "${yellow}📝 NOTE: This is a 1-day trial account${nc}"
            echo -e "${yellow}⏰ Will expire automatically on: $exp${nc}"
            echo -e "${yellow}👥 Active trials: $((current_trials + 1))${nc}"
            
        else
            echo -e "${red}ERROR${nc}: Xray service failed to start after restart"
            echo -e "${yellow}Please check system logs: journalctl -u xray${nc}"
        fi
    else
        echo -e "${red}ERROR${nc}: Failed to restart Xray service"
        echo -e "${yellow}Please check system logs${nc}"
    fi
else
    echo -e "${red}ERROR${nc}: Failed to create trial account"
    echo -e "${yellow}Config has been restored from backup${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-trojan
