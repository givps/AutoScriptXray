#!/bin/bash
# ==========================================
# Check Trojan Users
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

# Function to extract Trojan users from config
get_trojan_users() {
    # Extract Trojan users - looking for #!# pattern used in your add-trojan script
    grep -E '^#! ' /etc/xray/config.json | awk '{print $2}'
}

# Function to check active connections for a user
check_user_connections() {
    local user="$1"
    local user_ips=()
    
    # Get IPs from access log for this user
    if [[ -f "/var/log/xray/access.log" ]]; then
        user_ips=($(grep -w "$user" /var/log/xray/access.log 2>/dev/null | \
                   awk '{print $3}' | cut -d: -f1 | sort | uniq))
    fi
    
    # Check if any of these IPs have active connections
    local active_ips=()
    for ip in "${user_ips[@]}"; do
        if netstat -anp 2>/dev/null | grep -q "ESTABLISHED.*xray.*$ip"; then
            active_ips+=("$ip")
        fi
    done
    
    echo "${active_ips[@]}"
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}        Trojan User Login Monitor      ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Domain: ${domain}${nc}"
echo -e "${yellow}IP: ${MYIP}${nc}"
echo ""

# Get all Trojan users
users=($(get_trojan_users))

if [[ ${#users[@]} -eq 0 ]]; then
    echo -e "${yellow}No Trojan users found in config${nc}"
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    # m-trojan
    exit 0
fi

# Temporary files
temp_user_ips="/tmp/trojan_user_ips.txt"
temp_other_ips="/tmp/trojan_other_ips.txt"

> "$temp_user_ips"
> "$temp_other_ips"

# Get all active Xray connections
active_connections=($(netstat -anp 2>/dev/null | grep ESTABLISHED | grep xray | \
                     awk '{print $5}' | cut -d: -f1 | sort | uniq))

# Check each user
active_users=0
for user in "${users[@]}"; do
    user_active_ips=($(check_user_connections "$user"))
    
    if [[ ${#user_active_ips[@]} -gt 0 ]]; then
        ((active_users++))
        echo -e "${green}User: $user${nc}"
        echo -e "${blue}Active IPs:${nc}"
        for i in "${!user_active_ips[@]}"; do
            echo -e "  $((i+1)). ${user_active_ips[i]}"
            echo "${user_active_ips[i]}" >> "$temp_user_ips"
        done
        echo -e "${red}=========================================${nc}"
    fi
done

# Find other IPs (not associated with known users)
for ip in "${active_connections[@]}"; do
    if ! grep -q "^$ip$" "$temp_user_ips" 2>/dev/null; then
        echo "$ip" >> "$temp_other_ips"
    fi
done

# Display other connections
if [[ -s "$temp_other_ips" ]]; then
    echo -e "${yellow}Other Active Connections:${nc}"
    other_ips=($(sort -u "$temp_other_ips"))
    for i in "${!other_ips[@]}"; do
        echo -e "  $((i+1)). ${other_ips[i]}"
    done
else
    echo -e "${yellow}No other active connections${nc}"
fi

echo -e "${red}=========================================${nc}"
echo -e "${green}Summary:${nc}"
echo -e "  Total Trojan Users: ${#users[@]}"
echo -e "  Active Users: $active_users"
echo -e "  Total Active IPs: $(sort -u "$temp_user_ips" "$temp_other_ips" 2>/dev/null | wc -l)"
echo -e "${red}=========================================${nc}"
echo ""

# Cleanup
rm -f "$temp_user_ips" "$temp_other_ips"

read -n 1 -s -r -p "Press any key to back on menu"
m-trojan


