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
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

clear

# Function to count VLess users
count_vless_users() {
    grep -c -E "^#& " "/usr/local/etc/xray/config.json"
}

NUMBER_OF_CLIENTS=$(count_vless_users)

if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}        Delete VLess Account          ${nc}"  # Changed to blue for consistency
    echo -e "${red}=========================================${nc}"
    echo -e "${yellow}  • You don't have any existing VLess clients!${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-vless
    exit 0
fi

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}        Delete VLess Account          ${nc}"  # Changed to blue
echo -e "${red}=========================================${nc}"
echo -e "${green}  No.  Username           Expired Date${nc}"  # Added header
echo -e "${red}=========================================${nc}"
grep -E "^#& " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2-3 | sort | uniq | nl -w 3 -s "   "
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
    m-vless
    exit 0
fi

# Validate user exists
if ! grep -q "^#& $user " "/usr/local/etc/xray/config.json"; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}        Delete VLess Account          ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}  • Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}  • Available users:${nc}"
    grep -E "^#& " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2 | sort | uniq | nl -w 3 -s "   "
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-vless
    exit 1
fi

# Get user expiry date
exp=$(grep -wE "^#& $user" "/usr/local/etc/xray/config.json" | head -1 | cut -d ' ' -f 3)

# Backup config before modification (safety measure)
cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Delete user from config
if sed -i "/^#& $user $exp/,/^},{/d" /usr/local/etc/xray/config.json 2>/dev/null; then
    # Also delete from gRPC section if exists
    sed -i "0,/^#& $user $exp/,/^},{/d" /usr/local/etc/xray/config.json 2>/dev/null
    
    # Restart Xray service
    if systemctl restart xray > /dev/null 2>&1; then
        # Remove client config file if exists
        rm -f "/home/vps/public_html/vless-$user.txt" 2>/dev/null
        
        # Remove from log file if exists
        sed -i "/Remarks.*: $user$/d" /var/log/create-vless.log 2>/dev/null
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}        Delete VLess Account          ${nc}"
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
        rm -f /usr/local/etc/xray/config.json.backup.* 2>/dev/null
    else
        echo -e "${red}  • Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}  • Restoring backup config...${nc}"
        cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
        systemctl restart xray > /dev/null 2>&1
    fi
else
    echo -e "${red}  • Error: Failed to delete user from config${nc}"
fi

echo ""
read -n 1 -s -r -p "   Press any key to back on menu"
m-vless
