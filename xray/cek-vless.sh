#!/bin/bash
# ==========================================
# Check VLess Users
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

# Function to extract VLess users from config
get_vless_users() {
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        return 1
    fi
    
    # Extract VLess users - looking for pattern used in add-vless script
    # Pattern: "### username expiry_date" and also check email field
    grep -E '^### ' /usr/local/etc/xray/config.json | awk '{print $2, $3}' | sort -u
}

# Function to get user details
get_user_details() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Get expiry date
    local exp=$(grep -E "^### $user " "$config_file" | head -1 | awk '{print $3}')
    
    # Get UUID
    local uuid=$(grep -A2 -B2 "\"email\": \"$user\"" "$config_file" | grep '"id":' | head -1 | cut -d'"' -f4)
    
    echo "$exp|$uuid"
}

# Function to check active connections for a user
check_user_connections() {
    local user="$1"
    local user_ips=()
    
    # Get IPs from access log for this user (using UUID)
    local user_details=$(get_user_details "$user")
    local uuid=$(echo "$user_details" | cut -d'|' -f2)
    
    if [[ -n "$uuid" && -f "/var/log/xray/access.log" ]]; then
        user_ips=($(grep "$uuid" /var/log/xray/access.log 2>/dev/null | \
                   grep "accepted" | \
                   awk '{print $3}' | cut -d: -f1 | sort -u | head -10))
    fi
    
    # Alternative: check by email/user in logs
    if [[ ${#user_ips[@]} -eq 0 && -f "/var/log/xray/access.log" ]]; then
        user_ips=($(grep -w "$user" /var/log/xray/access.log 2>/dev/null | \
                   grep "accepted" | \
                   awk '{print $3}' | cut -d: -f1 | sort -u | head -10))
    fi
    
    echo "${user_ips[@]}"
}

# Function to check service status
check_service_status() {
    if systemctl is-active --quiet xray; then
        echo -e "${green}Active${nc}"
    else
        echo -e "${red}Inactive${nc}"
    fi
}

# Function to check log file existence
check_log_files() {
    local logs_exist=0
    if [[ -f "/var/log/xray/access.log" ]]; then
        ((logs_exist++))
    fi
    if [[ -f "/var/log/xray/error.log" ]]; then
        ((logs_exist++))
    fi
    echo $logs_exist
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}        VLess User Monitor            ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Domain: ${domain}${nc}"
echo -e "${yellow}IP: ${MYIP}${nc}"
echo -e "${yellow}Xray Status: $(check_service_status)${nc}"
echo ""

# Check if Xray config exists
if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
    echo -e "${red}ERROR: Xray config file not found!${nc}"
    echo -e "${yellow}Please check if Xray is properly installed.${nc}"
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 1
fi

# Check log files
log_files=$(check_log_files)
if [[ $log_files -eq 0 ]]; then
    echo -e "${yellow}Warning: Xray log files not found${nc}"
    echo -e "${yellow}Connection monitoring may not work properly${nc}"
    echo ""
fi

# Get all VLess users
echo -e "${blue}Scanning for VLess users...${nc}"
users_info=($(get_vless_users))

if [[ ${#users_info[@]} -eq 0 ]]; then
    echo -e "${yellow}No VLess users found in config${nc}"
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 0
fi

# Display all users first
echo -e "${green}VLess Users Found: ${#users_info[@]}${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${blue}Username           Expiry Date     Status${nc}"
echo -e "${red}=========================================${nc}"

active_count=0
today=$(date +%Y-%m-%d)

declare -A user_expiry_map
declare -A user_uuid_map

for user_info in "${users_info[@]}"; do
    user=$(echo "$user_info" | awk '{print $1}')
    exp=$(echo "$user_info" | awk '{print $2}')
    
    user_expiry_map["$user"]="$exp"
    
    # Get UUID for each user
    user_details=$(get_user_details "$user")
    uuid=$(echo "$user_details" | cut -d'|' -f2)
    user_uuid_map["$user"]="$uuid"
    
    # Check if expired
    if [[ "$exp" < "$today" ]]; then
        status="${red}EXPIRED${nc}"
    else
        status="${green}ACTIVE${nc}"
        ((active_count++))
    fi
    
    printf "%-18s %-15s %b\n" "$user" "$exp" "$status"
done

echo -e "${red}=========================================${nc}"
echo ""

# Check active connections if logs exist
if [[ $log_files -gt 0 ]]; then
    echo -e "${blue}Checking Active Connections...${nc}"
    echo -e "${red}=========================================${nc}"
    
    # Temporary files
    temp_user_ips=$(mktemp)
    temp_other_ips=$(mktemp)
    
    > "$temp_user_ips"
    > "$temp_other_ips"
    
    # Get all active Xray connections
    active_connections=($(ss -tnp 2>/dev/null | grep xray | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort -u))
    
    active_users_count=0
    total_active_ips=0
    
    # Check each user for active connections
    for user in "${!user_expiry_map[@]}"; do
        user_active_ips=($(check_user_connections "$user"))
        
        if [[ ${#user_active_ips[@]} -gt 0 ]]; then
            ((active_users_count++))
            total_active_ips=$((total_active_ips + ${#user_active_ips[@]}))
            
            echo -e "${green}✓ $user${nc}"
            echo -e "${yellow}  Active IPs (${#user_active_ips[@]}):${nc}"
            for i in "${!user_active_ips[@]}"; do
                echo -e "    $((i+1)). ${user_active_ips[i]}"
                echo "${user_active_ips[i]}" >> "$temp_user_ips"
            done
            echo ""
        fi
    done
    
    # Find other IPs (not associated with known users)
    other_count=0
    for ip in "${active_connections[@]}"; do
        if [[ ! "$ip" =~ ^(127\.|10\.|172\.|192\.168\.) ]] && \
           ! grep -q "^$ip$" "$temp_user_ips" 2>/dev/null; then
            echo "$ip" >> "$temp_other_ips"
            ((other_count++))
        fi
    done
    
    # Display other connections
    if [[ -s "$temp_other_ips" ]]; then
        other_ips=($(sort -u "$temp_other_ips"))
        echo -e "${yellow}Other Active Connections (${#other_ips[@]}):${nc}"
        for i in "${!other_ips[@]}"; do
            echo -e "  $((i+1)). ${other_ips[i]}"
        done
        echo ""
    fi
    
    # Summary
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}Connection Summary:${nc}"
    echo -e "  Total VLess Users    : ${#user_expiry_map[@]}"
    echo -e "  Active (Not Expired) : $active_count"
    echo -e "  Users with Connections: $active_users_count"
    echo -e "  Total Active IPs     : $total_active_ips"
    echo -e "  Unknown IPs          : $other_count"
    
    # Cleanup
    rm -f "$temp_user_ips" "$temp_other_ips"
    
else
    echo -e "${yellow}Note: Install logs not available for connection monitoring${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}Account Summary:${nc}"
    echo -e "  Total VLess Users    : ${#user_expiry_map[@]}"
    echo -e "  Active (Not Expired) : $active_count"
    echo -e "  Expired Accounts     : $((${#user_expiry_map[@]} - active_count))"
fi

echo -e "${red}=========================================${nc}"

# Show recent log entries if available
if [[ -f "/var/log/xray/access.log" ]]; then
    echo ""
    echo -e "${blue}Recent Activity (last 5 entries):${nc}"
    echo -e "${red}=========================================${nc}"
    tail -5 /var/log/xray/access.log 2>/dev/null | while read line; do
        echo -e "${yellow}$line${nc}"
    done
    echo -e "${red}=========================================${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-vless 2>/dev/null || exit 0
