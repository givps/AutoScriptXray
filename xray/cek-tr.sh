#!/bin/bash
# ==========================================
# Check Trojan Users - IMPROVED VERSION
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

# Function to extract Trojan users from config using jq
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
    if jq -e '.inbounds[] | select(.tag == "trojan-ws")' "$config_file" > /dev/null 2>&1; then
        jq -r '.inbounds[] | select(.tag == "trojan-ws") | .settings.clients[] | .email // empty' "$config_file" 2>/dev/null
    fi
}

# Function to get user expiry info from comments (if exists)
get_user_expiry() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Try to find expiry from comment format #! user expiry
    grep -E "^#! $user " "$config_file" 2>/dev/null | awk '{print $3}' || echo "Unknown"
}

# Function to check active connections for a user
check_user_connections() {
    local user="$1"
    local active_ips=()
    
    # Check recent connections from access.log (last 10 minutes)
    if [[ -f "/var/log/xray/access.log" ]]; then
        local recent_logs=$(find /var/log/xray/ -name "access.log*" -mmin -10 2>/dev/null)
        
        for log_file in $recent_logs; do
            if [[ -f "$log_file" ]]; then
                # Extract IPs with successful connections for this user
                local user_ips=$(grep -w "accepted.*email: $user" "$log_file" 2>/dev/null | \
                               awk '{print $3}' | cut -d: -f1 | sort -u)
                
                for ip in $user_ips; do
                    # Check if IP has active connections in netstat/ss
                    if ss -tnp 2>/dev/null | grep -q "ESTAB.*xray.*$ip:" || \
                       netstat -tnp 2>/dev/null | grep -q "ESTABLISHED.*xray.*$ip:"; then
                        active_ips+=("$ip")
                    fi
                done
            fi
        done
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${active_ips[@]}" | sort -u
}

# Function to count total connections per IP
count_connections_per_ip() {
    local ip="$1"
    ss -tnp 2>/dev/null | grep "ESTAB.*xray.*$ip:" | wc -l
}

# Function to get user location info (optional)
get_ip_location() {
    local ip="$1"
    # Using ipapi.co for location info
    curl -s "https://ipapi.co/$ip/country/" 2>/dev/null || echo "Unknown"
}

# Main script
echo -e "${red}=========================================${nc}"
echo -e "${blue}        TROJAN USER MONITOR           ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Domain: ${domain}${nc}"
echo -e "${yellow}Server IP: ${MYIP}${nc}"
echo -e "${yellow}Time: $(date)${nc}"
echo ""

# Get all Trojan users
echo -e "${yellow}Loading Trojan users...${nc}"
users=($(get_trojan_users))

if [[ ${#users[@]} -eq 0 ]] || [[ -z "${users[0]}" ]]; then
    echo -e "${red}No Trojan users found in configuration${nc}"
    echo -e "${yellow}Checking config file structure...${nc}"
    
    # Debug info
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${blue}Available inbound tags:${nc}"
        jq -r '.inbounds[] | .tag' /usr/local/etc/xray/config.json 2>/dev/null || echo "Cannot read config"
    fi
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    exit 0
fi

echo -e "${green}Found ${#users[@]} Trojan user(s)${nc}"
echo ""

# Display all users first
echo -e "${blue}ALL TROJAN USERS:${nc}"
echo -e "${red}=========================================${nc}"
for i in "${!users[@]}"; do
    user="${users[i]}"
    expiry=$(get_user_expiry "$user")
    echo -e "$((i+1)). ${green}$user${nc} - Expiry: ${yellow}$expiry${nc}"
done
echo -e "${red}=========================================${nc}"
echo ""

# Check active connections
echo -e "${blue}ACTIVE CONNECTIONS:${nc}"
echo -e "${red}=========================================${nc}"

active_users_count=0
total_connections=0

for user in "${users[@]}"; do
    active_ips=($(check_user_connections "$user"))
    
    if [[ ${#active_ips[@]} -gt 0 ]]; then
        ((active_users_count++))
        echo -e "${green}✓ $user${nc}"
        
        for ip in "${active_ips[@]}"; do
            connection_count=$(count_connections_per_ip "$ip")
            location=$(get_ip_location "$ip")
            ((total_connections += connection_count))
            
            echo -e "  └─ ${blue}IP: $ip${nc}"
            echo -e "     ├─ Connections: ${yellow}$connection_count${nc}"
            echo -e "     └─ Location: ${yellow}$location${nc}"
        done
        echo ""
    fi
done

if [[ $active_users_count -eq 0 ]]; then
    echo -e "${yellow}No active connections found${nc}"
    echo -e "${yellow}Note: Checking connections from last 10 minutes${nc}"
fi

# Show recent connections from logs (last 30 minutes)
echo -e "${blue}RECENT CONNECTIONS (last 30 minutes):${nc}"
echo -e "${red}=========================================${nc}"

recent_connections=$(find /var/log/xray/ -name "access.log*" -mmin -30 2>/dev/null | \
                    xargs -r grep -h "accepted.*trojan-ws" 2>/dev/null | \
                    tail -20 | head -10)

if [[ -n "$recent_connections" ]]; then
    echo "$recent_connections" | while read -r line; do
        timestamp=$(echo "$line" | awk '{print $1, $2}')
        user=$(echo "$line" | grep -o 'email: [^ ]*' | cut -d' ' -f2)
        ip=$(echo "$line" | awk '{print $3}' | cut -d: -f1)
        target=$(echo "$line" | grep -o 'tcp:[^ ]*' | cut -d: -f2-)
        
        if [[ -n "$user" ]]; then
            echo -e "${green}$timestamp${nc} - ${blue}$user${nc} from ${yellow}$ip${nc} to ${cyan}$target${nc}"
        fi
    done
else
    echo -e "${yellow}No recent connections found in logs${nc}"
fi

echo -e "${red}=========================================${nc}"

# Summary
echo -e "${green}SUMMARY:${nc}"
echo -e "  Total Users: ${#users[@]}"
echo -e "  Active Users: $active_users_count"
echo -e "  Total Connections: $total_connections"
echo -e "  Monitoring Period: Last 10 minutes"

# Service status
echo -e "${blue}SERVICE STATUS:${nc}"
if systemctl is-active --quiet xray; then
    echo -e "  Xray: ${green}RUNNING${nc}"
else
    echo -e "  Xray: ${red}STOPPED${nc}"
fi

if systemctl is-active --quiet nginx; then
    echo -e "  Nginx: ${green}RUNNING${nc}"
else
    echo -e "  Nginx: ${red}STOPPED${nc}"
fi

echo -e "${red}=========================================${nc}"

read -n 1 -s -r -p "Press any key to back on menu"
m-trojan
