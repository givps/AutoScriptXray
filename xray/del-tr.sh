#!/bin/bash
# ==========================================
# Delete Trojan Account - IMPROVED VERSION
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

# Function to get Trojan users using jq
get_trojan_users() {
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found${nc}" >&2
        return 1
    fi
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Extract Trojan WS users
    jq -r '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | .email // empty' "$config_file" 2>/dev/null | grep -v '^$'
}

# Function to count Trojan users
count_trojan_users() {
    get_trojan_users | wc -l
}

# Function to backup config
backup_config() {
    local backup_file="/usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S)"
    if cp "/usr/local/etc/xray/config.json" "$backup_file" 2>/dev/null; then
        echo "$backup_file"
    else
        echo ""
    fi
}

# Function to restore config on error
restore_config() {
    local backup_file="$1"
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "/usr/local/etc/xray/config.json"
        rm -f "$backup_file"
        echo -e "${green}✓ Config restored from backup${nc}"
        return 0
    else
        echo -e "${red}✗ Backup file not found${nc}"
        return 1
    fi
}

# Function to delete user using jq
delete_trojan_user() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found${nc}" >&2
        return 1
    fi
    
    # Backup config
    local backup_file=$(backup_config)
    if [[ -z "$backup_file" ]]; then
        echo -e "${red}ERROR: Failed to create backup${nc}" >&2
        return 1
    fi
    
    echo -e "${yellow}Backup created: $backup_file${nc}"
    
    # Delete user from Trojan WS
    echo -e "${yellow}Removing user from Trojan WS...${nc}"
    jq '(.inbounds[] | select(.tag == "trojan-ws").settings.clients) |= map(select(.email != "'"$user"'"))' "$config_file" > "${config_file}.tmp"
    
    if [[ $? -ne 0 ]] || [[ ! -f "${config_file}.tmp" ]]; then
        echo -e "${red}ERROR: Failed to update Trojan WS config${nc}" >&2
        restore_config "$backup_file"
        return 1
    fi
    
    mv "${config_file}.tmp" "$config_file"
    
    # Delete user from Trojan gRPC if exists
    if jq -e '.inbounds[] | select(.tag == "trojan-grpc")' "$config_file" > /dev/null 2>&1; then
        echo -e "${yellow}Removing user from Trojan gRPC...${nc}"
        jq '(.inbounds[] | select(.tag == "trojan-grpc").settings.clients) |= map(select(.email != "'"$user"'"))' "$config_file" > "${config_file}.tmp"
        
        if [[ $? -eq 0 ]] && [[ -f "${config_file}.tmp" ]]; then
            mv "${config_file}.tmp" "$config_file"
            echo -e "${green}✓ User removed from Trojan gRPC${nc}"
        else
            echo -e "${yellow}⚠ Failed to remove from Trojan gRPC (may not exist)${nc}"
        fi
    fi
    
    # Verify user was removed
    local user_still_exists=$(jq '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | select(.email == "'"$user"'")' "$config_file" 2>/dev/null | wc -l)
    
    if [[ $user_still_exists -eq 0 ]]; then
        echo -e "${green}✓ User successfully removed from config${nc}"
        rm -f "$backup_file" 2>/dev/null
        return 0
    else
        echo -e "${red}ERROR: User still exists in config after deletion${nc}" >&2
        restore_config "$backup_file"
        return 1
    fi
}

# Function to get user expiry (from comments if exists)
get_user_expiry() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Try to find expiry from comment format #! user expiry
    grep -E "^#! $user " "$config_file" 2>/dev/null | head -1 | awk '{print $3}' || echo "Unknown"
}

# Main script
NUMBER_OF_CLIENTS=$(count_trojan_users)

if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         DELETE TROJAN ACCOUNT         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    echo -e "${yellow}  • No Trojan users found${nc}"
    echo -e "${yellow}  • Check if Xray config exists${nc}"
    echo ""
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Display current users
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}         DELETE TROJAN ACCOUNT         ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  No.  Username           Expired Date${nc}"
echo -e "${red}=========================================${nc}"

# Display users with numbers
users=($(get_trojan_users))
for i in "${!users[@]}"; do
    user="${users[i]}"
    expiry=$(get_user_expiry "$user")
    printf "  %-3s %-18s %s\n" "$((i+1))" "$user" "$expiry"
done

echo -e "${red}=========================================${nc}"
echo -e "${yellow}  • Total Users: $NUMBER_OF_CLIENTS${nc}"
echo -e "${yellow}  • [NOTE] Press Enter to cancel${nc}"
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
    echo -e "${blue}         DELETE TROJAN ACCOUNT         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}  • Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}  • Available users:${nc}"
    for i in "${!users[@]}"; do
        echo -e "     $((i+1)). ${users[i]}"
    done
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 1
fi

# Get user expiry date
exp=$(get_user_expiry "$user")

# Confirm deletion
echo ""
echo -e "${yellow}  • Confirm deletion:${nc}"
echo -e "     Username: $user"
echo -e "     Expiry: $exp"
echo ""
read -rp "   Type 'YES' to confirm: " confirmation

if [[ "$confirmation" != "YES" ]]; then
    echo -e "${yellow}  • Deletion cancelled${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Delete user from config
echo ""
echo -e "${yellow}Deleting user $user...${nc}"
if delete_trojan_user "$user"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray; then
        echo -e "${green}✓ Xray service restarted successfully${nc}"
        
        # Remove client config file if exists
        rm -f "/home/vps/public_html/trojan-$user.txt" 2>/dev/null
        rm -f "/home/vps/public_html/trojan-$user.json" 2>/dev/null
        
        # Remove from log file if exists
        sed -i "/Remarks.*: $user$/d" /var/log/create-trojan.log 2>/dev/null
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}         DELETE TROJAN ACCOUNT         ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}  • ACCOUNT DELETED SUCCESSFULLY${nc}"
        echo ""
        echo -e "${blue}  • Details:${nc}"
        echo -e "     Username    : $user"
        echo -e "     Expired On  : $exp"
        echo -e "     Remaining   : $((NUMBER_OF_CLIENTS - 1)) users"
        echo ""
        echo -e "${green}  • Cleanup completed:${nc}"
        echo -e "     ✓ Removed from Xray config"
        echo -e "     ✓ Removed client config files"
        echo -e "     ✓ Service restarted"
        echo -e "${red}=========================================${nc}"
    else
        echo -e "${red}  • Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}  • Please check system logs${nc}"
        echo -e "${red}=========================================${nc}"
    fi
else
    echo -e "${red}  • Error: Failed to delete user${nc}"
    echo -e "${yellow}  • Config restored from backup${nc}"
    echo -e "${red}=========================================${nc}"
fi

echo ""
read -n 1 -s -r -p "   Press any key to back on menu"
m-trojan
