#!/bin/bash
# ==========================================
# Check Shadowsocks Users
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

# Function to extract Shadowsocks users from config - PERFECT MATCH!
get_ss_users() {
    # Extract using EXACT pattern from your add script: ###
    grep -E '^### ' /etc/xray/config.json | awk '{print $2}'
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

# Function to get user details from config
get_user_details() {
    local user="$1"
    # Get password and method from config
    local password=$(grep -A 2 "### $user" /etc/xray/config.json | grep '"password":' | cut -d'"' -f4 2>/dev/null)
    local method=$(grep -A 2 "### $user" /etc/xray/config.json | grep '"method":' | cut -d'"' -f4 2>/dev/null)
    local expiry=$(grep "### $user" /etc/xray/config.json | awk '{print $3}')
    
    echo "$password|$method|$expiry"
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}     Shadowsocks User Login Monitor    ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Domain: ${domain}${nc}"
echo -e "${yellow}IP: ${MYIP}${nc}"
echo ""

# Get all Shadowsocks users
users=($(get_ss_users))

if [[ ${#users[@]} -eq 0 ]]; then
    echo -e "${yellow}No Shadowsocks users found in config${nc}"
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-ssws
    exit 0
fi

# Check each user
active_users=0
echo -e "${green}Checking ${#users[@]} Shadowsocks Users...${nc}"
echo ""

for user in "${users[@]}"; do
    user_details=($(get_user_details "$user" | tr '|' ' '))
    password="${user_details[0]}"
    method="${user_details[1]}"
    expiry="${user_details[2]}"
    
    user_active_ips=($(check_user_connections "$user"))
    
    if [[ ${#user_active_ips[@]} -gt 0 ]]; then
        ((active_users++))
        echo -e "${green}✓ User: $user${nc}"
        echo -e "  Password: ${password:0:8}... | Method: $method"
        echo -e "  Expiry: $expiry"
        echo -e "  ${blue}Active IPs:${nc}"
        for i in "${!user_active_ips[@]}"; do
            echo -e "    $((i+1)). ${user_active_ips[i]}"
        done
        echo -e "${red}=========================================${nc}"
    fi
done

# Display inactive users
if [[ $active_users -lt ${#users[@]} ]]; then
    echo -e "${yellow}Inactive Shadowsocks Users:${nc}"
    for user in "${users[@]}"; do
        user_active_ips=($(check_user_connections "$user"))
        if [[ ${#user_active_ips[@]} -eq 0 ]]; then
            user_details=($(get_user_details "$user" | tr '|' ' '))
            expiry="${user_details[2]}"
            echo -e "  - $user (Expiry: $expiry)"
        fi
    done
    echo -e "${red}=========================================${nc}"
fi

# Summary
echo -e "${green}Summary:${nc}"
echo -e "  Total SS Users: ${#users[@]}"
echo -e "  Active Users: $active_users"
echo -e "  Inactive Users: $(( ${#users[@]} - active_users ))"
echo -e "${red}=========================================${nc}"

# Check if any users are expired
current_date=$(date +"%Y-%m-%d")
expired_count=0
for user in "${users[@]}"; do
    user_details=($(get_user_details "$user" | tr '|' ' '))
    expiry="${user_details[2]}"
    if [[ "$expiry" < "$current_date" ]]; then
        ((expired_count++))
    fi
done

if [[ $expired_count -gt 0 ]]; then
    echo -e "${red}Warning: $expired_count user(s) expired${nc}"
fi

echo ""
read -n 1 -s -r -p "Press any key to back on menu"
m-ssws

