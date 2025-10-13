#!/bin/bash
# ==========================================
# Create Trial Trojan Account - IMPROVED VERSION
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

# Function to generate random username
generate_trial_username() {
    local prefix="trial"
    local random_chars=$(</dev/urandom tr -dc A-Z0-9 | head -c6)
    echo "${prefix}${random_chars}"
}

# Function to check if username already exists
username_exists() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if command -v jq &> /dev/null; then
        jq '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | select(.email == "'"$user"'")' "$config_file" 2>/dev/null | grep -q .
    else
        grep -q "\"email\": \"$user\"" "$config_file" 2>/dev/null
    fi
}

# Function to add user using jq
add_trojan_user() {
    local user="$1"
    local uuid="$2"
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
    
    # Add to Trojan WS
    echo -e "${yellow}Adding trial user to Trojan WS...${nc}"
    jq '(.inbounds[] | select(.tag == "trojan-ws").settings.clients) += [{"password": "'"$uuid"'", "email": "'"$user"'"}]' "$config_file" > "${config_file}.tmp"
    
    if [[ $? -ne 0 ]] || [[ ! -f "${config_file}.tmp" ]]; then
        echo -e "${red}ERROR${nc}: Failed to update Trojan WS"
        return 1
    fi
    
    mv "${config_file}.tmp" "$config_file"
    
    # Verify the user was added
    local user_added=$(jq '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | select(.email == "'"$user"'") | .email' "$config_file" 2>/dev/null)
    
    if [[ "$user_added" == "\"$user\"" ]]; then
        echo -e "${green}✓ Trial user successfully added to Trojan WS${nc}"
        
        # Add comment for expiry tracking
        sed -i "/\"clients\": \[/a #! $user $exp" "$config_file" 2>/dev/null
        
        # Clean up backup file on success
        rm -f "$backup_file" 2>/dev/null
        return 0
    else
        echo -e "${red}ERROR${nc}: Trial user not found in config after update"
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

# Display header
echo -e "${red}=========================================${nc}"
echo -e "${blue}         CREATE TROJAN TRIAL          ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Generating trial account...${nc}"
echo ""

# Generate unique trial user
max_attempts=5
attempt=1
while [[ $attempt -le $max_attempts ]]; do
    user=$(generate_trial_username)
    if ! username_exists "$user"; then
        break
    fi
    echo -e "${yellow}Username $user exists, generating new one...${nc}"
    ((attempt++))
    sleep 1
done

if [[ $attempt -gt $max_attempts ]]; then
    echo -e "${red}ERROR${nc}: Failed to generate unique username after $max_attempts attempts"
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
    trojanlink="trojan://${uuid}@${domain}:${tls}?path=%2Ftrojan-ws&security=tls&host=${domain}&type=ws&sni=${domain}#${user}-Trial"
    trojanlink2="trojan://${uuid}@${domain}:${ntls}?path=%2Ftrojan-ws&security=none&host=${domain}&type=ws#${user}-Trial"
    
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray; then
        echo -e "${green}✓ Xray service restarted successfully${nc}"
        
        # Create client config file
        CLIENT_DIR="/home/vps/public_html"
        mkdir -p "$CLIENT_DIR"
        
        cat > "$CLIENT_DIR/trojan-$user.txt" <<-END
# ==========================================
# Trojan Trial Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp (1 day trial)
# ==========================================

# Trojan WS TLS
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

# IMPORTANT: This is a TRIAL account
# Expires in 24 hours from creation

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
        echo -e "${red}=========================================${nc}"
        echo -e "${green}Link TLS (WS)${nc}"
        echo -e "${trojanlink}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}Link none TLS (WS)${nc}"
        echo -e "${trojanlink2}"
        echo -e "${red}=========================================${nc}"
        echo -e "Expired On     : $exp ${yellow}(1 day trial)${nc}"
        echo -e "Config File    : $CLIENT_DIR/trojan-$user.txt"
        echo -e "${red}=========================================${nc}"
        echo ""
        
        # Log the creation
        echo "$(date): Created trial Trojan account '$user' (exp: $exp)" >> /var/log/trial-trojan.log
        
        echo -e "${green}✅ TRIAL ACCOUNT CREATED SUCCESSFULLY${nc}"
        echo -e "${yellow}📝 NOTE: This is a 1-day trial account${nc}"
        echo -e "${yellow}⏰ Will expire automatically on: $exp${nc}"
        
    else
        echo -e "${red}ERROR${nc}: Failed to restart Xray service"
        echo -e "${yellow}Please check system logs and restart manually${nc}"
    fi
else
    echo -e "${red}ERROR${nc}: Failed to create trial account"
    echo -e "${yellow}Config has been restored from backup${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-trojan
