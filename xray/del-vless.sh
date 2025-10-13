#!/bin/bash
# ==========================================
# Delete VLess Account
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

# Function to count VLess users
count_vless_users() {
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        echo "0"
        return 1
    fi
    grep -c -E "^### " "/usr/local/etc/xray/config.json" 2>/dev/null || echo "0"
}

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

# Function to delete user from config
delete_user_from_config() {
    local user="$1"
    local exp="$2"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Use awk untuk menghapus user section yang lebih reliable
    awk -v user="$user" -v exp="$exp" '
    BEGIN { skip = 0; in_user_section = 0 }
    /^### '${user}' '${exp}'$/ { 
        skip = 1
        in_user_section = 1
        next
    }
    skip && /^},{/ { 
        skip = 0
        in_user_section = 0
        next
    }
    skip && in_user_section && /\"email\": \"'${user}'\"/ {
        skip = 1
        next
    }
    !skip { print }
    ' "$config_file" > "$temp_file"
    
    # Verify the deletion worked by checking if user still exists
    if grep -q "^### $user $exp" "$temp_file" || \
       grep -q "\"email\": \"$user\"" "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi
    
    # Verify JSON validity
    if python3 -m json.tool "$temp_file" > /dev/null 2>&1; then
        mv "$temp_file" "$config_file"
        chmod 644 "$config_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}        Delete VLess Account          ${nc}"
echo -e "${red}=========================================${nc}"

# Check if config file exists
if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
    echo -e "${red}Error: Xray config file not found!${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

NUMBER_OF_CLIENTS=$(count_vless_users)

if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
    echo ""
    echo -e "${yellow}You don't have any existing VLess clients!${nc}"
    echo ""
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 0
fi

# Display current users
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}        Delete VLess Account          ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  Username           Expired Date${nc}"
echo -e "${red}=========================================${nc}"

# Display users with better formatting
grep -E "^### " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2-3 | sort -k2 | while read user exp; do
    printf "  %-18s %s\n" "$user" "$exp"
done

echo -e "${red}=========================================${nc}"
echo -e "${yellow}Total Users: $NUMBER_OF_CLIENTS${nc}"
echo ""
echo -e "${blue}Enter username to delete${nc}"
echo -e "${yellow}• [NOTE] Press Enter without username to cancel${nc}"
echo -e "${red}=========================================${nc}"

read -rp "Input Username : " user

# Check if user input is empty
if [[ -z "$user" ]]; then
    echo -e "${yellow}Operation cancelled${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 0
fi

# Validate user exists
if ! grep -q "^### $user " "/usr/local/etc/xray/config.json"; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}        Delete VLess Account          ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}Available users:${nc}"
    grep -E "^### " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2 | sort | uniq
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Get user expiry date
exp=$(grep -wE "^### $user" "/usr/local/etc/xray/config.json" | head -1 | cut -d ' ' -f 3)

# Confirm deletion
echo ""
echo -e "${yellow}Are you sure you want to delete user: $user?${nc}"
echo -e "${yellow}Expiry date: $exp${nc}"
echo -e "${red}This action cannot be undone!${nc}"
echo ""
read -rp "Confirm deletion (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}Deletion cancelled${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 0
fi

# Backup config before modification
echo -e "${yellow}Creating backup...${nc}"
backup_file=$(backup_config)

if [[ "$backup_file" == "error" ]]; then
    echo -e "${red}Error: Failed to create backup!${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Delete user from config
echo -e "${yellow}Deleting user from config...${nc}"
if delete_user_from_config "$user" "$exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray > /dev/null 2>&1; then
        # Remove client config file if exists
        rm -f "/home/vps/public_html/vless-$user.txt" 2>/dev/null
        rm -f "/home/vps/public_html/vless-$user.json" 2>/dev/null
        
        # Remove from log file if exists
        [[ -f "/var/log/create-vless.log" ]] && sed -i "/$user/d" "/var/log/create-vless.log" 2>/dev/null
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}        Delete VLess Account          ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}✓ Account Deleted Successfully${nc}"
        echo ""
        echo -e "${blue}Details:${nc}"
        echo -e "  • Client Name : $user"
        echo -e "  • Expired On  : $exp"
        echo -e "  • Remaining Users: $(count_vless_users)"
        echo ""
        echo -e "${green}Service restarted successfully${nc}"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
        
        # Log the deletion
        echo "$(date): Deleted VLess account $user (was exp: $exp)" >> /var/log/delete-vless.log 2>/dev/null
        
    else
        echo -e "${red}Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}Restoring backup config...${nc}"
        restore_config "$backup_file"
        systemctl restart xray > /dev/null 2>&1
        echo -e "${red}Changes have been reverted${nc}"
    fi
else
    echo -e "${red}Error: Failed to delete user from config${nc}"
    echo -e "${yellow}Restoring backup config...${nc}"
    restore_config "$backup_file"
    echo -e "${red}No changes were made${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless 2>/dev/null || exit 0
