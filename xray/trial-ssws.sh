#!/bin/bash
# ==========================================
# Create Trial Shadowsocks Account
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
    local cipher="$3"
    local exp="$4"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Add user to shadowsocks-ws section
    awk -v user="$user" -v uuid="$uuid" -v cipher="$cipher" -v exp="$exp" '
    /#ssws$/ {
        print $0
        print "### " user " " exp
        print "},{\"password\": \"" uuid "\",\"method\": \"" cipher "\",\"email\": \"" user "\""
        next
    }
    /#ssgrpc$/ {
        print $0
        print "### " user " " exp
        print "},{\"password\": \"" uuid "\",\"method\": \"" cipher "\",\"email\": \"" user "\""
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
echo -e "${blue}        Trial Shadowsocks Account      ${nc}"
echo -e "${red}=========================================${nc}"

# Validate domain exists
if [[ -z "$domain" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-ssws 2>/dev/null || exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS none TLS" | cut -d: -f2 | sed 's/ //g' | head -1)"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Shadowsocks ports in log file."
    echo -e "${yellow}Please check if Shadowsocks is properly installed.${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-ssws 2>/dev/null || exit 1
fi

# Generate trial user
user="trial$(</dev/urandom tr -dc A-Z0-9 | head -c4 2>/dev/null || echo $RANDOM | md5sum | head -c4)"
cipher="aes-128-gcm"
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
    m-ssws 2>/dev/null || exit 1
fi

# Add user to config.json
echo -e "${yellow}Adding user to config...${nc}"
if add_user_to_config "$user" "$uuid" "$cipher" "$exp"; then
    # Restart services
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray > /dev/null 2>&1; then
        systemctl restart cron > /dev/null 2>&1
        
        # Create shadowsocks links
        shadowsocks_base64="$cipher:$uuid"
        shadowsocks_base64e=$(echo -n "$shadowsocks_base64" | base64 -w0 2>/dev/null || echo "base64_error")
        
        # Generate Shadowsocks links
        if [[ "$shadowsocks_base64e" != "base64_error" ]]; then
            shadowsockslink="ss://${shadowsocks_base64e}@${domain}:${tls}?path=%2Fss-ws&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
            shadowsockslink2="ss://${shadowsocks_base64e}@${domain}:${ntls}?path=%2Fss-ws&security=none&host=${domain}&type=ws#${user}"
            shadowsockslink1="ss://${shadowsocks_base64e}@${domain}:${tls}?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni=${domain}#${user}"
        else
            shadowsockslink="ss://ERROR_GENERATING_LINK"
            shadowsockslink2="ss://ERROR_GENERATING_LINK"
            shadowsockslink1="ss://ERROR_GENERATING_LINK"
        fi
        
        # Create client config file
        CLIENT_DIR="/home/vps/public_html"
        mkdir -p "$CLIENT_DIR"
        
        cat > "$CLIENT_DIR/ss-$user.txt" <<-END
# ==========================================
# Shadowsocks Trial Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp (1 day trial)
# ==========================================

# Shadowsocks WS TLS
${shadowsockslink}

# Shadowsocks WS None TLS  
${shadowsockslink2}

# Shadowsocks gRPC
${shadowsockslink1}

# Configuration Details:
- Domain: $domain
- Port TLS: $tls
- Port None TLS: $ntls
- Password: $uuid
- Method: $cipher
- Path: /ss-ws
- Service Name: ss-grpc
- Expiry: $exp (1 day trial)

# Manual Configuration:
- Server: $domain
- Port: $tls (TLS) / $ntls (Non-TLS)
- Password: $uuid
- Encryption: $cipher
- Plugin: v2ray-plugin
- Plugin Options: tls;host=$domain;path=/ss-ws

END

        # Display results
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}        Trial Shadowsocks Account      ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}✓ Trial Account Created Successfully${nc}"
        echo ""
        echo -e "${blue}Account Details:${nc}"
        echo -e "  • Remarks       : ${user} ${yellow}(TRIAL)${nc}"
        echo -e "  • Domain        : ${domain}"
        echo -e "  • Port TLS      : ${tls}"
        echo -e "  • Port Non-TLS  : ${ntls}"
        echo -e "  • Password      : ${uuid}"
        echo -e "  • Cipher        : ${cipher}"
        echo -e "  • Network       : WS/gRPC"
        echo -e "  • Path          : /ss-ws"
        echo -e "  • Service Name  : ss-grpc"
        echo -e "  • Expiry        : $exp ${yellow}(1 day trial)${nc}"
        echo ""
        
        echo -e "${green}Configuration Links:${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}WS with TLS:${nc}"
        echo -e "${shadowsockslink}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}WS without TLS:${nc}"
        echo -e "${shadowsockslink2}"
        echo -e "${red}=========================================${nc}"
        echo -e "${yellow}gRPC:${nc}"
        echo -e "${shadowsockslink1}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${blue}Config File:${nc} $CLIENT_DIR/ss-$user.txt"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
        
        # Log the creation
        echo "$(date): Created trial SS account $user (exp: $exp)" >> /var/log/trial-ss.log 2>/dev/null
        
        echo -e "${green}SUCCESS${nc}: Trial Shadowsocks account created!"
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
m-ssws 2>/dev/null || exit 0
