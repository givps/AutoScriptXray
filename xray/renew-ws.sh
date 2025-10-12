#!/bin/bash
# ==========================================
# Renew VMess Account
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

# Function to count VMess users
count_vmess_users() {
    grep -c -E "^### " "/usr/local/etc/xray/config.json"
}

# Function to backup config
backup_config() {
    local backup_file="/usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S)"
    cp /usr/local/etc/xray/config.json "$backup_file" 2>/dev/null
    echo "$backup_file"
}

NUMBER_OF_CLIENTS=$(count_vmess_users)

if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           Renew VMess           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    echo -e "${yellow}You have no existing VMess clients!${nc}"
    echo ""
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess
    exit 0
fi

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}           Renew VMess           ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  Username           Expired Date${nc}"
echo -e "${red}=========================================${nc}"
grep -E "^### " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2-3 | while read user exp; do
    printf "  %-18s %s\n" "$user" "$exp"
done
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Total Users: $NUMBER_OF_CLIENTS${nc}"
echo -e "${yellow}• [NOTE] Press Enter to cancel${nc}"
echo -e "${red}=========================================${nc}"
echo ""

read -rp "Input Username : " user

# Check if user input is empty
if [[ -z "$user" ]]; then
    echo -e "${yellow}Operation cancelled${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess
    exit 0
fi

# Validate user exists
if ! grep -q "^### $user " "/usr/local/etc/xray/config.json"; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           Renew VMess           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}Available users:${nc}"
    grep -E "^### " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2 | sort | uniq
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess
    exit 1
fi

# Get current expiry date
current_exp=$(grep -wE "^### $user" "/usr/local/etc/xray/config.json" | head -1 | cut -d ' ' -f 3)

# Get renewal days with validation
while true; do
    read -p "Extend for (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [ $masaaktif -gt 0 ]; then
        break
    else
        echo -e "${red}Error: Please enter a valid number of days${nc}"
    fi
done

# Calculate new expiry date
now=$(date +%Y-%m-%d)
d1=$(date -d "$current_exp" +%s 2>/dev/null || date -d "$now" +%s)
d2=$(date -d "$now" +%s)

# Handle expired accounts
if [[ $d1 -lt $d2 ]]; then
    days_remaining=0
    new_exp=$(date -d "$masaaktif days" +"%Y-%m-%d")
    echo -e "${yellow}Note: Account was expired. Renewing from today.${nc}"
else
    days_remaining=$(( (d1 - d2) / 86400 ))
    total_days=$((days_remaining + masaaktif))
    new_exp=$(date -d "$total_days days" +"%Y-%m-%d")
fi

# Backup config before modification
backup_file=$(backup_config)

# Update expiry date in config
if sed -i "s/^### $user $current_exp/### $user $new_exp/" /usr/local/etc/xray/config.json 2>/dev/null; then
    # Also update in gRPC section if exists
    sed -i "0,/^### $user $current_exp/s/^### $user $current_exp/### $user $new_exp/" /usr/local/etc/xray/config.json 2>/dev/null
    
    # Restart Xray service
    if systemctl restart xray > /dev/null 2>&1; then
        # Update client config file if exists
        if [[ -f "/home/vps/public_html/vmess-$user.txt" ]]; then
            sed -i "s/Expired On  : $current_exp/Expired On  : $new_exp/" "/home/vps/public_html/vmess-$user.txt" 2>/dev/null
            sed -i "s/Expiry: $current_exp/Expiry: $new_exp/" "/home/vps/public_html/vmess-$user.txt" 2>/dev/null
        fi
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${green} VMess Account Successfully Renewed ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${blue}Details:${nc}"
        echo -e "  Client Name    : $user"
        echo -e "  Old Expiry     : $current_exp"
        echo -e "  New Expiry     : $new_exp"
        echo -e "  Days Added     : $masaaktif"
        if [[ $days_remaining -gt 0 ]]; then
            echo -e "  Days Remaining : $days_remaining → $((days_remaining + masaaktif))"
        fi
        echo ""
        echo -e "${green}Service restarted successfully${nc}"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
        
        # Log the renewal
        echo "$(date): Renewed VMess account $user from $current_exp to $new_exp (+$masaaktif days)" >> /var/log/renew-vmess.log 2>/dev/null
    else
        echo -e "${red}Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}Restoring backup config...${nc}"
        cp "$backup_file" /usr/local/etc/xray/config.json 2>/dev/null
        systemctl restart xray > /dev/null 2>&1
    fi
else
    echo -e "${red}Error: Failed to update expiry date${nc}"
    echo -e "${yellow}Restoring backup config...${nc}"
    cp "$backup_file" /usr/local/etc/xray/config.json 2>/dev/null
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess
