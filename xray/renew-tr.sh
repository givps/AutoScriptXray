#!/bin/bash
# ==========================================
# Renew Trojan Account - IMPROVED VERSION
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

# Function to get user expiry (from comments if exists)
get_user_expiry() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Try to find expiry from comment format #! user expiry
    grep -E "^#! $user " "$config_file" 2>/dev/null | head -1 | awk '{print $3}' || echo "Unknown"
}

# Function to update user expiry in comments
update_user_expiry() {
    local user="$1"
    local old_exp="$2"
    local new_exp="$3"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Backup config
    local backup_file=$(backup_config)
    if [[ -z "$backup_file" ]]; then
        echo -e "${red}ERROR: Failed to create backup${nc}" >&2
        return 1
    fi
    
    echo -e "${yellow}Backup created: $backup_file${nc}"
    
    # Update expiry in comments using sed (since comments are not in JSON structure)
    if sed -i "s/^#! $user $old_exp/#! $user $new_exp/g" "$config_file" 2>/dev/null; then
        echo -e "${green}✓ Expiry updated in config comments${nc}"
        
        # Verify the update
        local current_exp=$(get_user_expiry "$user")
        if [[ "$current_exp" == "$new_exp" ]]; then
            echo -e "${green}✓ Expiry verification successful${nc}"
            rm -f "$backup_file" 2>/dev/null
            return 0
        else
            echo -e "${red}ERROR: Expiry update verification failed${nc}" >&2
            restore_config "$backup_file"
            return 1
        fi
    else
        echo -e "${red}ERROR: Failed to update expiry in config${nc}" >&2
        restore_config "$backup_file"
        return 1
    fi
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

# Function to calculate date difference
date_diff() {
    local date1="$1"
    local date2="$2"
    local d1=$(date -d "$date1" +%s 2>/dev/null)
    local d2=$(date -d "$date2" +%s 2>/dev/null)
    
    if [[ -z "$d1" ]] || [[ -z "$d2" ]]; then
        echo "0"
        return
    fi
    
    echo $(( (d1 - d2) / 86400 ))
}

# Main script
NUMBER_OF_CLIENTS=$(count_trojan_users)

if [[ ${NUMBER_OF_CLIENTS} -eq 0 ]]; then
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           RENEW TROJAN ACCOUNT        ${nc}"
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
echo -e "${blue}           RENEW TROJAN ACCOUNT        ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${green}  No.  Username           Expired Date${nc}"
echo -e "${red}=========================================${nc}"

# Display users with numbers and status
users=($(get_trojan_users))
today=$(date +%Y-%m-%d)

for i in "${!users[@]}"; do
    user="${users[i]}"
    expiry=$(get_user_expiry "$user")
    
    # Check if expired
    days_left=$(date_diff "$expiry" "$today")
    if [[ $days_left -lt 0 ]]; then
        status="${red}EXPIRED${nc}"
    elif [[ $days_left -eq 0 ]]; then
        status="${yellow}TODAY${nc}"
    elif [[ $days_left -le 7 ]]; then
        status="${yellow}$days_left days${nc}"
    else
        status="${green}$days_left days${nc}"
    fi
    
    printf "  %-3s %-18s %-12s [%b]\n" "$((i+1))" "$user" "$expiry" "$status"
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
    echo -e "${blue}           RENEW TROJAN ACCOUNT        ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}  • Error: User '$user' not found!${nc}"
    echo ""
    echo -e "${yellow}  • Available users:${nc}"
    for i in "${!users[@]}"; do
        expiry=$(get_user_expiry "${users[i]}")
        echo -e "     $((i+1)). ${users[i]} - $expiry"
    done
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 1
fi

# Get current expiry and calculate status
current_exp=$(get_user_expiry "$user")
today=$(date +%Y-%m-%d)
days_left=$(date_diff "$current_exp" "$today")

echo ""
echo -e "${blue}  • Current Account Status:${nc}"
echo -e "     Username    : $user"
echo -e "     Expiry Date : $current_exp"

if [[ $days_left -lt 0 ]]; then
    echo -e "     Status      : ${red}EXPIRED ($((-$days_left)) days ago)${nc}"
    echo -e "     Renewal     : Will renew from today"
elif [[ $days_left -eq 0 ]]; then
    echo -e "     Status      : ${yellow}EXPIRES TODAY${nc}"
else
    echo -e "     Status      : ${green}Active ($days_left days left)${nc}"
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
if [[ $days_left -lt 0 ]]; then
    # Account expired - renew from today
    new_exp=$(date -d "$masaaktif days" +"%Y-%m-%d")
    echo -e "${yellow}  • Note: Account was expired. Renewing from today.${nc}"
else
    # Account active - extend from current expiry
    new_exp=$(date -d "$current_exp + $masaaktif days" +"%Y-%m-%d")
fi

# Confirm renewal
echo ""
echo -e "${yellow}  • Renewal Summary:${nc}"
echo -e "     Old Expiry : $current_exp"
echo -e "     New Expiry : $new_exp"
echo -e "     Days Added : $masaaktif"
echo ""
read -rp "   Type 'YES' to confirm renewal: " confirmation

if [[ "$confirmation" != "YES" ]]; then
    echo -e "${yellow}  • Renewal cancelled${nc}"
    echo ""
    read -n 1 -s -r -p "   Press any key to back on menu"
    m-trojan
    exit 0
fi

# Update expiry date
echo ""
echo -e "${yellow}Updating expiry date for $user...${nc}"
if update_user_expiry "$user" "$current_exp" "$new_exp"; then
    # Restart Xray service
    echo -e "${yellow}Restarting Xray service...${nc}"
    if systemctl restart xray; then
        echo -e "${green}✓ Xray service restarted successfully${nc}"
        
        # Update client config file if exists
        if [[ -f "/home/vps/public_html/trojan-$user.txt" ]]; then
            sed -i "s/Expired On  : $current_exp/Expired On  : $new_exp/g" "/home/vps/public_html/trojan-$user.txt" 2>/dev/null
            sed -i "s/Expiry: $current_exp/Expiry: $new_exp/g" "/home/vps/public_html/trojan-$user.txt" 2>/dev/null
            echo -e "${green}✓ Client config file updated${nc}"
        fi
        
        # Display success message
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${green}      TROJAN ACCOUNT RENEWED         ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${blue}  • Account Details:${nc}"
        echo -e "     Username    : $user"
        echo -e "     Old Expiry  : $current_exp"
        echo -e "     New Expiry  : $new_exp"
        echo -e "     Days Added  : $masaaktif"
        
        if [[ $days_left -ge 0 ]]; then
            new_days_left=$((days_left + masaaktif))
            echo -e "     Total Days  : $new_days_left days remaining"
        fi
        
        echo ""
        echo -e "${green}  • Services Updated:${nc}"
        echo -e "     ✓ Xray configuration"
        echo -e "     ✓ Client config files"
        echo -e "     ✓ Service restarted"
        echo -e "${red}=========================================${nc}"
        
        # Log the renewal
        echo "$(date): Renewed Trojan account '$user' from '$current_exp' to '$new_exp' (+$masaaktif days)" >> /var/log/renew-trojan.log 2>/dev/null
    else
        echo -e "${red}  • Error: Failed to restart Xray service${nc}"
        echo -e "${yellow}  • Please check system logs${nc}"
        echo -e "${red}=========================================${nc}"
    fi
else
    echo -e "${red}  • Error: Failed to update expiry date${nc}"
    echo -e "${yellow}  • Config restored from backup${nc}"
    echo -e "${red}=========================================${nc}"
fi

echo ""
read -n 1 -s -r -p "   Press any key to back on menu"
m-trojan
