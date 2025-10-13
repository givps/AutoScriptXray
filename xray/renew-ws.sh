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
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "unknown")
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null || echo "unknown")

clear

# Function to count VMess users
count_vmess_users() {
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

# Function to validate date format
validate_date() {
    local date_str="$1"
    if date -d "$date_str" "+%Y-%m-%d" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to update expiry
update_expiry() {
    local user="$1"
    local old_exp="$2"
    local new_exp="$3"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Update expiry date using sed
    if sed "s/^### $user $old_exp$/### $user $new_exp/g" "$config_file" > "$temp_file" 2>/dev/null; then
        # Verify the update worked
        if grep -q "^### $user $new_exp$" "$temp_file"; then
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
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}           Renew VMess Account         ${nc}"
echo -e "${red}=========================================${nc}"

# Check if config file exists
if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
    echo -e "${red}Error: Xray config file not found!${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

NUMBER_OF_CLIENTS=$(count_vmess_users)

if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
    echo ""
    echo -e "${yellow}You have no existing VMess clients!${nc}"
    echo ""
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 0
fi

# Display current users
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}           Renew VMess Account         ${nc}"
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
echo -e "${blue}Enter username to renew${nc}"
echo -e "${yellow}• [NOTE] Press Enter without username to cancel${nc}"
echo -e "${red}=========================================${nc}"

read -rp "Input Username : " user

# Check if user input is empty
if [[ -z "$user" ]]; then
    echo -e "${yellow}Operation cancelled${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 0
fi

# Validate user exists
if ! grep -q "^### $user " "/usr/local/etc/xray/config.json"; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           Renew VMess Account         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}Available users:${nc}"
    grep -E "^### " "/usr/local/etc/xray/config.json" | cut -d ' ' -f 2 | sort | uniq
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Get current expiry date
current_exp=$(grep -wE "^### $user" "/usr/local/etc/xray/config.json" | head -1 | cut -d ' ' -f 3)

# Validate current expiry date format
if ! validate_date "$current_exp"; then
    echo -e "${red}Error: Invalid current expiry date format: $current_exp${nc}"
    echo -e "${yellow}Please check the config file manually${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Get renewal days with validation
while true; do
    echo ""
    read -p "Extend for (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [ $masaaktif -gt 0 ] && [ $masaaktif -le 3650 ]; then
        break
    else
        echo -e "${red}Error: Please enter a valid number of days (1-3650)${nc}"
    fi
done

# Calculate new expiry date
now=$(date +%Y-%m-%d)
current_epoch=$(date -d "$current_exp" +%s 2>/dev/null)
now_epoch=$(date -d "$now" +%s)

# Handle expired accounts - if current expiry is in past, extend from today
if [[ $current_epoch -lt $now_epoch ]]; then
    days_remaining=0
    new_exp=$(date -d "$now + $masaaktif days" +"%Y-%m-%d")
    echo -e "${yellow}Note: Account was expired. Renewing from today.${nc}"
else
    days_remaining=$(( (current_epoch - now_epoch) / 86400 ))
    total_days=$((days_remaining + masaaktif))
    new_exp=$(date -d "$now + $total_days days" +"%Y-%m-%d")
fi

# Validate new expiry date
if ! validate_date "$new_exp"; then
    echo -e "${red}Error: Failed to calculate valid new expiry date${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Get UUID for logging
uuid=$(grep -A2 -B2 "\"email\": \"$user\"" "/usr/local/etc/xray/config.json" | grep '"id":' | head -1 | cut -d'"' -f4)

# Display renewal summary
echo ""
echo -e "${blue}Renewal Summary:${nc}"
echo -e "  • User          : $user"
echo -e "  • Current Expiry: $current_exp"
echo -e "  • Days Added    : $masaaktif"
echo -e "  • New Expiry    : $new_exp"
if [[ -n "$uuid" ]]; then
    echo -e "  • UUID          : ${uuid:0:8}..."
fi
if [[ $days_remaining -gt 0 ]]; then
    echo -e "  • Days Remaining: $days_remaining → $((days_remaining + masaaktif))"
fi
echo ""

# Confirm renewal
read -rp "Confirm renewal? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}Renewal cancelled${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 0
fi

# Backup config before modification
echo -e "${yellow}Creating backup...${nc}"
backup_file=$(backup_config)

if [[ "$backup_file" == "error" ]]; then
    echo -e "${red}Error: Failed to create backup!${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vmess 2>/dev/null || exit 1
fi

# Update expiry date in config
echo -e "${yellow}Updating expiry date...${nc}"
if update_expiry "$user" "$current_exp" "$new_exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray > /dev/null 2>&1; then
        # Update client config file if exists
        if [[ -f "/home/vps/public_html/vmess-$user.txt" ]]; then
            sed -i "s/Expired On  : $current_exp/Expired On  : $new_exp/" "/home/vps/public_html/vmess-$user.txt" 2>/dev/null
            sed -i "s/Expiry: $current_exp/Expiry: $new_exp/" "/home/vps/public_html/vmess-$user.txt" 2>/dev/null
            sed -i "s/# Generated: .*/# Generated: $(date)/" "/home/vps/public_html/vmess-$user.txt" 2>/dev/null
        fi
        
        # Update JSON config file if exists
        if [[ -f "/home/vps/public_html/vmess-$user.json" ]]; then
            sed -i "s/\"expiry\": \"$current_exp\"/\"expiry\": \"$new_exp\"/" "/home/vps/public_html/vmess-$user.json" 2>/dev/null
        fi
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}           Renew VMess Account         ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${green}✓ VMess Account Successfully Renewed${nc}"
        echo ""
        echo -e "${blue}Details:${nc}"
        echo -e "  • Client Name    : $user"
        echo -e "  • Old Expiry     : $current_exp"
        echo -e "  • New Expiry     : $new_exp"
        echo -e "  • Days Added     : $masaaktif"
        if [[ -n "$uuid" ]]; then
            echo -e "  • UUID          : ${uuid:0:8}..."
        fi
        if [[ $days_remaining -gt 0 ]]; then
            echo -e "  • Days Remaining : $days_remaining → $((days_remaining + masaaktif))"
        fi
        echo ""
        echo -e "${green}Service restarted successfully${nc}"
        echo -e "${red}=========================================${nc}"
        
        # Clean up backup file
        rm -f "$backup_file" 2>/dev/null
        
        # Log the renewal
        echo "$(date): Renewed VMess account $user (UUID: ${uuid:0:8}...) from $current_exp to $new_exp (+$masaaktif days)" >> /var/log/renew-vmess.log 2>/dev/null
        
    else
        echo -e "${red}Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}Restoring backup config...${nc}"
        restore_config "$backup_file"
        systemctl restart xray > /dev/null 2>&1
        echo -e "${red}Changes have been reverted${nc}"
    fi
else
    echo -e "${red}Error: Failed to update expiry date${nc}"
    echo -e "${yellow}Restoring backup config...${nc}"
    restore_config "$backup_file"
    echo -e "${red}No changes were made${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vmess 2>/dev/null || exit 0
