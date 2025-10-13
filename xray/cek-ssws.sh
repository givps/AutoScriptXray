#!/bin/bash
# ==========================================
# Check Shadowsocks Users - IMPROVED VERSION
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

# Function to get Shadowsocks users using jq
get_ss_users() {
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found${nc}" >&2
        return 1
    fi
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Extract Shadowsocks WS users
    jq -r '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[] | .email // empty' "$config_file" 2>/dev/null | grep -v '^$'
}

# Function to get user details using jq
get_user_details() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Get password and method from config
    local password=$(jq -r '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[] | select(.email == "'"$user"'") | .password' "$config_file" 2>/dev/null)
    local method=$(jq -r '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[] | select(.email == "'"$user"'") | .method' "$config_file" 2>/dev/null)
    
    # Get expiry from comments if exists
    local expiry=$(grep -E "^#! $user " "$config_file" 2>/dev/null | head -1 | awk '{print $3}')
    
    if [[ -z "$expiry" ]]; then
        expiry="Unknown"
    fi
    
    echo "$password|$method|$expiry"
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
                    # Check if IP has active connections in ss/netstat
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

# Function to count connections per IP
count_connections_per_ip() {
    local ip="$1"
    ss -tnp 2>/dev/null | grep "ESTAB.*xray.*$ip:" | wc -l
}

# Function to get IP location (optional)
get_ip_location() {
    local ip="$1"
    # Using ipapi.co for location info
    curl -s "https://ipapi.co/$ip/country/" 2>/dev/null || echo "Unknown"
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
echo -e "${red}=========================================${nc}"
echo -e "${blue}      SHADOWSOCKS USER MONITOR         ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${yellow}Domain: ${domain}${nc}"
echo -e "${yellow}Server IP: ${MYIP}${nc}"
echo -e "${yellow}Time: $(date)${nc}"
echo ""

# Get all Shadowsocks users
echo -e "${yellow}Loading Shadowsocks users...${nc}"
users=($(get_ss_users))

if [[ ${#users[@]} -eq 0 ]] || [[ -z "${users[0]}" ]]; then
    echo -e "${red}No Shadowsocks users found in configuration${nc}"
    echo -e "${yellow}Checking config file structure...${nc}"
    
    # Debug info
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${blue}Available inbound tags:${nc}"
        jq -r '.inbounds[] | .tag' /usr/local/etc/xray/config.json 2>/dev/null || echo "Cannot read config"
    fi
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-ssws
    exit 0
fi

echo -e "${green}Found ${#users[@]} Shadowsocks user(s)${nc}"
echo ""

# Display all users first
echo -e "${blue}ALL SHADOWSOCKS USERS:${nc}"
echo -e "${red}=========================================${nc}"

today=$(date +%Y-%m-%d)
for i in "${!users[@]}"; do
    user="${users[i]}"
    user_details=($(get_user_details "$user" | tr '|' ' '))
    method="${user_details[1]}"
    expiry="${user_details[2]}"
    
    # Check if expired
    if [[ "$expiry" != "Unknown" ]]; then
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
    else
        status="${yellow}NO EXPIRY${nc}"
    fi
    
    printf "  %-3s %-18s %-12s %-10s [%b]\n" "$((i+1))" "$user" "$expiry" "$method" "$status"
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
        user_details=($(get_user_details "$user" | tr '|' ' '))
        method="${user_details[1]}"
        expiry="${user_details[2]}"
        
        echo -e "${green}✓ $user${nc}"
        echo -e "  └─ Method: ${blue}$method${nc} | Expiry: ${yellow}$expiry${nc}"
        
        for ip in "${active_ips[@]}"; do
            connection_count=$(count_connections_per_ip "$ip")
            location=$(get_ip_location "$ip")
            ((total_connections += connection_count))
            
            echo -e "     ├─ IP: ${blue}$ip${nc}"
            echo -e "     │  ├─ Connections: ${yellow}$connection_count${nc}"
            echo -e "     │  └─ Location: ${yellow}$location${nc}"
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
                    xargs -r grep -h "accepted.*ss-ws" 2>/dev/null | \
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

# Check expired users
expired_count=0
expiring_soon_count=0
for user in "${users[@]}"; do
    user_details=($(get_user_details "$user" | tr '|' ' '))
    expiry="${user_details[2]}"
    
    if [[ "$expiry" != "Unknown" ]]; then
        days_left=$(date_diff "$expiry" "$today")
        if [[ $days_left -lt 0 ]]; then
            ((expired_count++))
        elif [[ $days_left -le 3 ]]; then
            ((expiring_soon_count++))
        fi
    fi
done

if [[ $expired_count -gt 0 ]]; then
    echo -e "  ${red}Expired Users: $expired_count${nc}"
fi

if [[ $expiring_soon_count -gt 0 ]]; then
    echo -e "  ${yellow}Expiring Soon (≤3 days): $expiring_soon_count${nc}"
fi

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
m-ssws
