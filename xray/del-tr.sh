#!/bin/bash
# ==========================================
# Delete Trojan Account
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

# Function to count Trojan users
count_trojan_users() {
    grep -c -E "^#! " "/etc/xray/config.json"
}

# Function to backup config
backup_config() {
    local backup_file="/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S)"
    cp /etc/xray/config.json "$backup_file" 2>/dev/null
    echo "$backup_file"
}

# Function to restore config on error
restore_config() {
    local backup_file="$1"
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" /etc/xray/config.json
        rm -f "$backup_file"
        echo -e "${green}Config restored from backup${nc}"
    fi
}

# Main script
NUMBER_OF_CLIENTS=$(count_trojan_users)

if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         Delete Trojan Account         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    echo -e "${yellow}  • You don't have any existing Trojan clients!${nc}"
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
echo -e "${blue}         Delete Trojan Account         ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  No.  Username           Expired Date${nc}"
echo -e "${red}=========================================${nc}"
grep -E "^#! " "/etc/xray/config.json" | cut -d ' ' -f 2-3 | sort | uniq | nl -w 3 -s "   "
echo -e "${red}=========================================${nc}"
echo -e "${yellow}  • Total Users: $NUMBER_OF_CLIENTS${nc}"
echo -e "${yellow}  • [NOTE] Press Enter to cancel${nc}"
echo -e "${red}=========================================${nc}"
echo ""

read -rp "   Input Username : " user

# Check if user input is empty
if [[ -z "$user" ]]; then
    echo -e "${yellow}  • Operation cancelled${nc}"
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Validate user exists
if ! grep -q "^#! $user " "/etc/xray/config.json"; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         Delete Trojan Account         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}  • Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}  • Available users:${nc}"
    grep -E "^#! " "/etc/xray/config.json" | cut -d ' ' -f 2 | sort | uniq | nl -w 3 -s "   "
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 1
fi

# Get user expiry date
exp=$(grep -wE "^#! $user" "/etc/xray/config.json" | head -1 | cut -d ' ' -f 3)

# Backup config before modification
backup_file=$(backup_config)

# Delete user from config
if sed -i "/^#! $user $exp/,/^},{/d" /etc/xray/config.json 2>/dev/null; then
    # Also delete from gRPC section if exists (second occurrence)
    sed -i "0,/^#! $user $exp/,/^},{/d" /etc/xray/config.json 2>/dev/null
    
    # Restart Xray service
    if systemctl restart xray > /dev/null 2>&1; then
        # Remove client config file if exists
        rm -f "/home/vps/public_html/trojan-$user.txt" 2>/dev/null
        
        # Remove from log file if exists
        sed -i "/Remarks.*: $user$/d" /var/log/create-trojan.log 2>/dev/null
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}         Delete Trojan Account         ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}  • Account Deleted Successfully${nc}"
        echo ""
        echo -e "${blue}  • Details:${nc}"
        echo -e "     Client Name : $user"
        echo -e "     Expired On  : $exp"
        echo -e "     Remaining   : $((NUMBER_OF_CLIENTS - 1)) users"
        echo ""
        echo -e "${green}  • Service restarted successfully${nc}"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
    else
        echo -e "${red}  • Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}  • Restoring backup config...${nc}"
        restore_config "$backup_file"
        systemctl restart xray > /dev/null 2>&1
        echo -e "${red}=========================================${nc}"
    fi
else
    echo -e "${red}  • Error: Failed to delete user from config${nc}"
    echo -e "${yellow}  • Restoring backup config...${nc}"
    restore_config "$backup_file"
    echo -e "${red}=========================================${nc}"
fi

echo ""
read -n 1 -s -r -p "   Press any key to back on menu"
m-trojan
