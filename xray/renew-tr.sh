#!/bin/bash
# ==========================================
# Renew Trojan Account - FIXED VERSION
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

# Function to get Trojan users using jq - FIXED
get_trojan_users() {
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
    
    # Extract Trojan WS users - FIXED: handle empty clients array
    if jq -e '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients' "$config_file" > /dev/null 2>&1; then
        local ws_users=$(jq -r '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]? | .email // empty' "$config_file" 2>/dev/null)
        if [[ -n "$ws_users" ]]; then
            while IFS= read -r user; do
                [[ -n "$user" ]] && users+=("$user")
            done <<< "$ws_users"
        fi
    fi
    
    # Extract Trojan gRPC users - FIXED: handle empty clients array
    if jq -e '.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients' "$config_file" > /dev/null 2>&1; then
        local grpc_users=$(jq -r '.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients[]? | .email // empty' "$config_file" 2>/dev/null)
        if [[ -n "$grpc_users" ]]; then
            while IFS= read -r user; do
                [[ -n "$user" ]] && users+=("$user")
            done <<< "$grpc_users"
        fi
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${users[@]}" | sort -u
}

# Function to count Trojan users - FIXED
count_trojan_users() {
    local users=($(get_trojan_users))
    echo ${#users[@]}
}

# Function to get user expiry - IMPROVED
get_user_expiry() {
    local user="$1"
    
    # Check multiple possible expiry storage locations
    local expiry_files=(
        "/etc/xray/user_expiry.txt"
        "/root/user_expiry.txt" 
        "/usr/local/etc/xray/user_expiry.txt"
        "/var/lib/xray/user_expiry.txt"
    )
    
    for file in "${expiry_files[@]}"; do
        if [[ -f "$file" ]]; then
            local expiry=$(grep -E "^$user " "$file" 2>/dev/null | awk '{print $2}')
            if [[ -n "$expiry" ]]; then
                echo "$expiry"
                return 0
            fi
        fi
    done
    
    # Check in config comments (fallback)
    local config_file="/usr/local/etc/xray/config.json"
    if [[ -f "$config_file" ]]; then
        local expiry=$(grep -E "#! $user " "$config_file" 2>/dev/null | awk '{print $3}')
        if [[ -n "$expiry" ]]; then
            echo "$expiry"
            return 0
        fi
    fi
    
    echo "Not Set"
}

# Function to update user expiry - IMPROVED
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
            echo -e "${green}✓ Expiry updated in: $(basename "$file")${nc}"
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

# Function to calculate date difference - IMPROVED
date_diff() {
    local date1="$1"
    local date2="$2"
    
    # Handle "Not Set" case
    if [[ "$date1" == "Not Set" ]] || [[ "$date2" == "Not Set" ]]; then
        echo "0"
        return
    fi
    
    # Validate date formats
    if ! date -d "$date1" &>/dev/null; then
        echo "0"
        return
    fi
    
    if ! date -d "$date2" &>/dev/null; then
        echo "0"
        return
    fi
    
    local d1=$(date -d "$date1" +%s 2>/dev/null)
    local d2=$(date -d "$date2" +%s 2>/dev/null)
    
    if [[ -z "$d1" ]] || [[ -z "$d2" ]]; then
        echo "0"
        return
    fi
    
    echo $(( (d1 - d2) / 86400 ))
}

# Function to validate date format
validate_date() {
    local date_str="$1"
    if date -d "$date_str" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get user services (WS/gRPC) - FIXED
get_user_services() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    local services=""
    
    if [[ ! -f "$config_file" ]]; then
        echo "Unknown"
        return
    fi
    
    # Check Trojan WS
    if jq -e '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[]? | select(.email == "'"$user"'")' "$config_file" &>/dev/null; then
        services="WS"
    fi
    
    # Check Trojan gRPC
    if jq -e '.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients[]? | select(.email == "'"$user"'")' "$config_file" &>/dev/null; then
        if [[ -n "$services" ]]; then
            services="$services+gRPC"
        else
            services="gRPC"
        fi
    fi
    
    echo "${services:-Unknown}"
}

# Function to update client config file - NEW
update_client_config() {
    local user="$1"
    local old_exp="$2"
    local new_exp="$3"
    local CLIENT_DIR="/home/vps/public_html"
    local client_file="$CLIENT_DIR/trojan-$user.txt"
    
    if [[ ! -f "$client_file" ]]; then
        echo -e "${yellow}⚠ Client config file not found: $(basename "$client_file")${nc}"
        return 1
    fi
    
    # Backup client file
    cp "$client_file" "$client_file.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null
    
    # Update expiry in client file
    local updated=0
    
    # Try different patterns
    if sed -i "s/Expired On  : $old_exp/Expired On  : $new_exp/g" "$client_file" 2>/dev/null; then
        ((updated++))
    fi
    
    if sed -i "s/Expiry: $old_exp/Expiry: $new_exp/g" "$client_file" 2>/dev/null; then
        ((updated++))
    fi
    
    if sed -i "s/Expired.*: $old_exp/Expired On  : $new_exp/g" "$client_file" 2>/dev/null; then
        ((updated++))
    fi
    
    # Generic replacement for any expiry line
    if grep -q "Expired On  :" "$client_file"; then
        sed -i "/Expired On  :/c\Expired On  : $new_exp" "$client_file" 2>/dev/null
        ((updated++))
    fi
    
    if [[ $updated -gt 0 ]]; then
        echo -e "${green}✓ Client config file updated${nc}"
        return 0
    else
        echo -e "${yellow}⚠ Could not update client config file${nc}"
        return 1
    fi
}

# Main script
echo -e "${yellow}Loading Trojan users...${nc}"
NUMBER_OF_CLIENTS=$(count_trojan_users)
users=($(get_trojan_users))

if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           RENEW TROJAN ACCOUNT        ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    echo -e "${yellow}  • No Trojan users found${nc}"
    echo -e "${yellow}  • Check if Xray config exists${nc}"
    echo ""
    
    # Debug info
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${blue}Config file exists but no users found${nc}"
        echo -e "${yellow}Available inbound tags:${nc}"
        jq -r '.inbounds[]? | .tag' /usr/local/etc/xray/config.json 2>/dev/null || echo "Cannot read config"
    else
        echo -e "${red}Config file not found${nc}"
    fi
    
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Display current users
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}           RENEW TROJAN ACCOUNT        ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  No.  Username           Expired     Services${nc}"
echo -e "${red}=========================================${nc}"

# Display users with numbers and status
today=$(date +%Y-%m-%d)

for i in "${!users[@]}"; do
    user="${users[i]}"
    expiry=$(get_user_expiry "$user")
    services=$(get_user_services "$user")
    
    # Check if expired
    if [[ "$expiry" == "Not Set" ]]; then
        status="${red}NOT SET${nc}"
        days_text=""
    else
        days_left=$(date_diff "$expiry" "$today")
        if [[ $days_left -lt 0 ]]; then
            status="${red}EXPIRED${nc}"
            days_text="($((-$days_left)) days ago)"
        elif [[ $days_left -eq 0 ]]; then
            status="${yellow}TODAY${nc}"
            days_text="(0 days)"
        elif [[ $days_left -le 7 ]]; then
            status="${yellow}$days_left days${nc}"
            days_text=""
        else
            status="${green}$days_left days${nc}"
            days_text=""
        fi
    fi
    
    printf "  %-3s %-18s %-12s %-8s [%b] %s\n" "$((i+1))" "$user" "$expiry" "$services" "$status" "$days_text"
done

echo -e "${red}=========================================${nc}"
echo -e "${yellow}  • Total Users: $NUMBER_OF_CLIENTS${nc}"
echo -e "${yellow}  • Services: WS=WebSocket, gRPC=gRPC${nc}"
echo -e "${yellow}  • [NOTE] Press Enter without input to cancel${nc}"
echo -e "${red}=========================================${nc}"
echo ""

read -rp "   Input Username : " user

# Check if user input is empty
if [[ -z "$user" ]]; then
    echo -e "${yellow}  • Operation cancelled${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Validate user exists
if ! printf '%s\n' "${users[@]}" | grep -q "^$user$"; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           RENEW TROJAN ACCOUNT        ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}  • Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}  • Available users:${nc}"
    for i in "${!users[@]}"; do
        expiry=$(get_user_expiry "${users[i]}")
        services=$(get_user_services "${users[i]}")
        echo -e "     $((i+1)). ${users[i]} - $expiry ($services)"
    done
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 1
fi

# Get current expiry and calculate status
current_exp=$(get_user_expiry "$user")
services=$(get_user_services "$user")
today=$(date +%Y-%m-%d)

echo ""
echo -e "${blue}  • Current Account Status:${nc}"
echo -e "     Username    : $user"
echo -e "     Services    : $services"
echo -e "     Expiry Date : $current_exp"

if [[ "$current_exp" == "Not Set" ]]; then
    echo -e "     Status      : ${red}EXPIRY NOT SET${nc}"
    echo -e "     Renewal     : Will set expiry from today"
    # Set default current expiry as today for calculation
    current_exp="$today"
    days_left=0
else
    days_left=$(date_diff "$current_exp" "$today")
    if [[ $days_left -lt 0 ]]; then
        echo -e "     Status      : ${red}EXPIRED ($((-$days_left)) days ago)${nc}"
        echo -e "     Renewal     : Will renew from today"
    elif [[ $days_left -eq 0 ]]; then
        echo -e "     Status      : ${yellow}EXPIRES TODAY${nc}"
    else
        echo -e "     Status      : ${green}Active ($days_left days left)${nc}"
    fi
fi

echo ""

# Get renewal days with validation
while true; do
    read -rp "   Extend for (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [[ $masaaktif -gt 0 ]]; then
        if [[ $masaaktif -gt 3650 ]]; then
            echo -e "${red}  • Error: Cannot extend more than 10 years${nc}"
            continue
        fi
        break
    else
        echo -e "${red}  • Error: Please enter a valid number of days${nc}"
    fi
done

# Calculate new expiry date
if [[ "$current_exp" == "Not Set" ]] || [[ $days_left -lt 0 ]]; then
    # Account expired or no expiry set - renew from today
    new_exp=$(date -d "$masaaktif days" +"%Y-%m-%d")
    echo -e "${yellow}  • Note: Setting new expiry from today.${nc}"
else
    # Account active - extend from current expiry
    new_exp=$(date -d "$current_exp + $masaaktif days" +"%Y-%m-%d")
fi

# Confirm renewal
echo ""
echo -e "${yellow}  • Renewal Summary:${nc}"
echo -e "     Username    : $user"
echo -e "     Services    : $services"
if [[ "$current_exp" != "Not Set" ]]; then
    echo -e "     Old Expiry  : $current_exp"
fi
echo -e "     New Expiry  : $new_exp"
echo -e "     Days Added  : $masaaktif"
echo ""
read -rp "   Confirm renewal? (y/N): " confirmation

if [[ "$confirmation" != "y" ]] && [[ "$confirmation" != "Y" ]]; then
    echo -e "${yellow}  • Renewal cancelled${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Update expiry date
echo ""
echo -e "${yellow}Updating expiry date for $user...${nc}"
if update_user_expiry "$user" "$new_exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray; then
        sleep 2
        if systemctl is-active --quiet xray; then
            echo -e "${green}✓ Xray service restarted successfully${nc}"
            
            # Update client config file
            echo -e "${yellow}Updating client configuration...${nc}"
            update_client_config "$user" "$current_exp" "$new_exp"
            
            # Display success message
            clear
            echo -e "${red}=========================================${nc}"
            echo -e "${green}      TROJAN ACCOUNT RENEWED         ${nc}"
            echo -e "${red}=========================================${nc}"
            echo ""
            echo -e "${blue}  • Account Details:${nc}"
            echo -e "     Username    : $user"
            echo -e "     Services    : $services"
            if [[ "$current_exp" != "Not Set" ]]; then
                echo -e "     Old Expiry  : $current_exp"
            fi
            echo -e "     New Expiry  : $new_exp"
            echo -e "     Days Added  : $masaaktif"
            
            if [[ "$current_exp" != "Not Set" ]] && [[ $days_left -ge 0 ]]; then
                new_days_left=$((days_left + masaaktif))
                echo -e "     Total Days  : $new_days_left days remaining"
            fi
            
            echo ""
            echo -e "${green}  • Services Updated:${nc}"
            echo -e "     ✓ Expiry database updated"
            echo -e "     ✓ Xray service restarted"
            echo -e "     ✓ Client config files updated"
            echo -e "${red}=========================================${nc}"
            
            # Log the renewal
            echo "$(date): Renewed Trojan account '$user' ($services) from '$current_exp' to '$new_exp' (+$masaaktif days)" >> /var/log/renew-trojan.log 2>/dev/null
        else
            echo -e "${red}  • Error: Xray service failed to start${nc}"
            echo -e "${yellow}  • Please check system logs: journalctl -u xray${nc}"
            echo -e "${red}=========================================${nc}"
        fi
    else
        echo -e "${red}  • Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}  • Please check system logs${nc}"
        echo -e "${red}=========================================${nc}"
    fi
else
    echo -e "${red}  • Error: Failed to update expiry date${nc}"
    echo -e "${red}=========================================${nc}"
fi

echo ""
read -n 1 -s -r -p "   Press any key to back on menu"
m-trojan
