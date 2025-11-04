#!/bin/bash
# ==========================================
# Delete Trojan Account - FIXED VERSION
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

# Function to delete user using jq - FIXED
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
    
    # Delete user from Trojan WS - FIXED: better error handling
    echo -e "${yellow}Removing user from Trojan WS...${nc}"
    if ! jq '(.inbounds[] | select(.tag == "trojan-ws").settings.clients) |= map(select(.email != "'"$user"'"))' "$config_file" > "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR: Failed to update Trojan WS config (jq error)${nc}" >&2
        restore_config "$backup_file"
        return 1
    fi
    
    if [[ ! -f "${config_file}.tmp" ]]; then
        echo -e "${red}ERROR: Temporary file not created${nc}" >&2
        restore_config "$backup_file"
        return 1
    fi
    
    # Validate the temp file before replacing
    if ! jq empty "${config_file}.tmp" 2>/dev/null; then
        echo -e "${red}ERROR: Generated config has invalid JSON${nc}" >&2
        rm -f "${config_file}.tmp"
        restore_config "$backup_file"
        return 1
    fi
    
    mv "${config_file}.tmp" "$config_file"
    echo -e "${green}✓ User removed from Trojan WS${nc}"
    
    # Delete user from Trojan gRPC if exists - FIXED: better check
    if jq -e '.inbounds[] | select(.tag == "trojan-grpc")' "$config_file" > /dev/null 2>&1; then
        echo -e "${yellow}Removing user from Trojan gRPC...${nc}"
        if jq '(.inbounds[] | select(.tag == "trojan-grpc").settings.clients) |= map(select(.email != "'"$user"'"))' "$config_file" > "${config_file}.tmp2" 2>/dev/null; then
            if jq empty "${config_file}.tmp2" 2>/dev/null; then
                mv "${config_file}.tmp2" "$config_file"
                echo -e "${green}✓ User removed from Trojan gRPC${nc}"
            else
                echo -e "${yellow}⚠ Invalid JSON generated for gRPC update, skipping${nc}"
                rm -f "${config_file}.tmp2"
            fi
        else
            echo -e "${yellow}⚠ Failed to update Trojan gRPC${nc}"
        fi
    fi
    
    # Verify user was removed - FIXED: check both WS and gRPC
    local user_still_exists=false
    
    # Check Trojan WS
    if jq -e '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | select(.email == "'"$user"'")' "$config_file" > /dev/null 2>&1; then
        user_still_exists=true
    fi
    
    # Check Trojan gRPC
    if jq -e '.inbounds[] | select(.tag == "trojan-grpc") | .settings.clients[] | select(.email == "'"$user"'")' "$config_file" > /dev/null 2>&1; then
        user_still_exists=true
    fi
    
    if [[ "$user_still_exists" == "false" ]]; then
        echo -e "${green}✓ User successfully removed from all configs${nc}"
        rm -f "$backup_file" 2>/dev/null
        return 0
    else
        echo -e "${red}ERROR: User still exists in config after deletion${nc}" >&2
        restore_config "$backup_file"
        return 1
    fi
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

# Function to cleanup user files - NEW
cleanup_user_files() {
    local user="$1"
    local files_removed=0
    
    # Client config files
    local client_files=(
        "/home/vps/public_html/trojan-$user.txt"
        "/home/vps/public_html/trojan-$user.json"
        "/home/vps/public_html/trojan-$user.conf"
    )
    
    for file in "${client_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo -e "     ✓ Removed: $(basename "$file")"
            ((files_removed++))
        fi
    done
    
    # Remove from log files
    local log_files=(
        "/var/log/create-trojan.log"
        "/var/log/xray/user.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            sed -i "/$user/d" "$log_file" 2>/dev/null
        fi
    done
    
    # Remove from expiry files
    local expiry_files=(
        "/etc/xray/user_expiry.txt"
        "/root/user_expiry.txt"
        "/usr/local/etc/xray/user_expiry.txt"
    )
    
    for expiry_file in "${expiry_files[@]}"; do
        if [[ -f "$expiry_file" ]]; then
            sed -i "/^$user /d" "$expiry_file" 2>/dev/null
        fi
    done
    
    return $files_removed
}

# Main script
echo -e "${yellow}Loading Trojan users...${nc}"
NUMBER_OF_CLIENTS=$(count_trojan_users)
users=($(get_trojan_users))

if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         DELETE TROJAN ACCOUNT         ${nc}"
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
echo -e "${blue}         DELETE TROJAN ACCOUNT         ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  No.  Username           Expired Date${nc}"
echo -e "${red}=========================================${nc}"

# Display users with numbers
for i in "${!users[@]}"; do
    user="${users[i]}"
    expiry=$(get_user_expiry "$user")
    printf "  %-3s %-18s %s\n" "$((i+1))" "$user" "$expiry"
done

echo -e "${red}=========================================${nc}"
echo -e "${yellow}  • Total Users: $NUMBER_OF_CLIENTS${nc}"
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
echo -e "     This action cannot be undone!"
echo ""
read -rp "   Type 'DELETE' to confirm: " confirmation

if [[ "$confirmation" != "DELETE" ]]; then
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
        
        # Wait a moment for service to stabilize
        sleep 2
        
        # Check if Xray is running
        if systemctl is-active --quiet xray; then
            echo -e "${green}✓ Xray service is running properly${nc}"
            
            # Cleanup user files
            echo -e "${yellow}Cleaning up user files...${nc}"
            cleanup_user_files "$user"
            
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
            echo -e "     ✓ Service restarted and verified"
            echo -e "     ✓ Client config files removed"
            echo -e "     ✓ Log entries cleaned"
            echo -e "${red}=========================================${nc}"
        else
            echo -e "${red}  • Error: Xray service failed to start after deletion${nc}"
            echo -e "${yellow}  • Please check system logs: journalctl -u xray${nc}"
            echo -e "${red}=========================================${nc}"
        fi
    else
        echo -e "${red}  • Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}  • Please check system logs${nc}"
        echo -e "${red}=========================================${nc}"
    fi
else
    echo -e "${red}  • Error: Failed to delete user from config${nc}"
    echo -e "${yellow}  • Config restored from backup${nc}"
    echo -e "${red}=========================================${nc}"
fi

echo ""
read -n 1 -s -r -p "   Press any key to back on menu"
m-trojan
