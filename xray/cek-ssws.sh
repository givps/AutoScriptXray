#!/bin/bash
# ==========================================
# Check Shadowsocks Users - FIXED VERSION
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

# Function to get Shadowsocks users using jq - FIXED
get_ss_users() {
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}ERROR: Config file not found${nc}" >&2
        return 1
    fi
    
    # Install jq if not exists
    if ! command -v jq &> /dev/null; then
        echo -e "${yellow}Installing jq...${nc}" >&2
        apt-get update > /dev/null 2>&1 && apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Check if config has valid JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${red}ERROR: Invalid JSON in config file${nc}" >&2
        return 1
    fi
    
    local users=()
    
    # Extract Shadowsocks WS users - FIXED: handle empty clients array
    if jq -e '.inbounds[] | select(.tag == "ss-ws") | .settings.clients' "$config_file" > /dev/null 2>&1; then
        local ws_users=$(jq -r '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]? | .email // empty' "$config_file" 2>/dev/null)
        if [[ -n "$ws_users" ]]; then
            while IFS= read -r user; do
                [[ -n "$user" ]] && users+=("$user")
            done <<< "$ws_users"
        fi
    fi
    
    # Extract Shadowsocks gRPC users - FIXED: handle empty clients array
    if jq -e '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients' "$config_file" > /dev/null 2>&1; then
        local grpc_users=$(jq -r '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]? | .email // empty' "$config_file" 2>/dev/null)
        if [[ -n "$grpc_users" ]]; then
            while IFS= read -r user; do
                [[ -n "$user" ]] && users+=("$user")
            done <<< "$grpc_users"
        fi
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${users[@]}" | sort -u
}

# Function to get user details using jq - FIXED
get_user_details() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    # Get password and method from config - FIXED: handle empty results
    local password=$(jq -r '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .password // empty' "$config_file" 2>/dev/null)
    local method=$(jq -r '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]? | select(.email == "'"$user"'") | .method // empty' "$config_file" 2>/dev/null)
    
    # If not found in WS, check gRPC
    if [[ -z "$password" ]]; then
        password=$(jq -r '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]? | select(.email == "'"$user"'") | .password // empty' "$config_file" 2>/dev/null)
        method=$(jq -r '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]? | select(.email == "'"$user"'") | .method // empty' "$config_file" 2>/dev/null)
    fi
    
    # Get expiry from database files - IMPROVED
    local expiry_files=(
        "/etc/xray/user_expiry.txt"
        "/root/user_expiry.txt" 
        "/usr/local/etc/xray/user_expiry.txt"
        "/var/lib/xray/user_expiry.txt"
    )
    
    local expiry="Not Set"
    for file in "${expiry_files[@]}"; do
        if [[ -f "$file" ]]; then
            local expiry_found=$(grep -E "^$user " "$file" 2>/dev/null | awk '{print $2}')
            if [[ -n "$expiry_found" ]]; then
                expiry="$expiry_found"
                break
            fi
        fi
    done
    
    # Fallback to config comments
    if [[ "$expiry" == "Not Set" ]]; then
        local expiry_comment=$(grep -E "^#! $user " "$config_file" 2>/dev/null | head -1 | awk '{print $3}')
        if [[ -n "$expiry_comment" ]]; then
            expiry="$expiry_comment"
        fi
    fi
    
    echo "$password|$method|$expiry"
}

# Function to get user services (WS/gRPC) - NEW
get_user_services() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    local services=""
    
    # Check Shadowsocks WS
    if jq -e '.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]? | select(.email == "'"$user"'")' "$config_file" &>/dev/null; then
        services="WS"
    fi
    
    # Check Shadowsocks gRPC
    if jq -e '.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]? | select(.email == "'"$user"'")' "$config_file" &>/dev/null; then
        if [[ -n "$services" ]]; then
            services="$services+gRPC"
        else
            services="gRPC"
        fi
    fi
    
    echo "${services:-Unknown}"
}

# Function to check active connections for a user - IMPROVED
check_user_connections() {
    local user="$1"
    local active_ips=()
    
    # Check Xray access log for recent connections (last 15 minutes)
    local log_files=(
        "/var/log/xray/access.log"
        "/var/log/xray/error.log"
    )
    
    # Find recent log files
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            # Check for user in logs (last 15 minutes)
            local recent_logs=$(find "$log_file" -type f -mmin -15 2>/dev/null)
            
            for log in $recent_logs; do
                if [[ -f "$log" ]]; then
                    # Extract IPs with successful connections for this user
                    # Match various log formats
                    local user_ips=$(grep -E "($user|email.*$user)" "$log" 2>/dev/null | \
                                   grep -E "(accepted|established)" 2>/dev/null | \
                                   awk '{print $3}' | cut -d: -f1 | sort -u)
                    
                    for ip in $user_ips; do
                        # Validate IP format
                        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                            # Check if IP has active connections
                            if ss -tnp 2>/dev/null | grep -q "ESTAB.*$ip:" || \
                               netstat -tnp 2>/dev/null | grep -q "ESTABLISHED.*$ip:"; then
                                active_ips+=("$ip")
                            elif [[ -n "$ip" ]]; then
                                # Include recently seen IPs even if not currently connected
                                active_ips+=("$ip-RECENT")
                            fi
                        fi
                    done
                fi
            done
        fi
    done
    
    # Remove duplicates and return
    printf '%s\n' "${active_ips[@]}" | sort -u
}

# Function to count connections per IP - IMPROVED
count_connections_per_ip() {
    local ip="$1"
    # Remove -RECENT suffix if present
    ip="${ip%-RECENT}"
    
    # Count connections using ss (more reliable)
    ss -tnp 2>/dev/null | grep "ESTAB.*$ip:" | wc -l
}

# Function to get IP location - IMPROVED
get_ip_location() {
    local ip="$1"
    # Remove -RECENT suffix if present
    ip="${ip%-RECENT}"
    
    # Validate IP format
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid IP"
        return
    fi
    
    # Try multiple location services
    local location=""
    
    # Method 1: ipapi.co
    location=$(curl -s --connect-timeout 3 "https://ipapi.co/$ip/country_name/" 2>/dev/null)
    if [[ -n "$location" ]] && [[ "$location" != "Undefined" ]]; then
        echo "$location"
        return
    fi
    
    # Method 2: ip-api.com
    location=$(curl -s --connect-timeout 3 "http://ip-api.com/line/$ip?fields=country" 2>/dev/null)
    if [[ -n "$location" ]] && [[ "$location" != "fail" ]]; then
        echo "$location"
        return
    fi
    
    echo "Unknown"
}

# Function to calculate date difference - IMPROVED
date_diff() {
    local date1="$1"
    local date2="$2"
    
    # Handle "Not Set" case
    if [[ "$date1" == "Not Set" ]] || [[ "$date2" == "Not Set" ]]; then
        echo "0"
        return
    fi
    
    # Validate date formats
    if ! date -d "$date1" &>/dev/null; then
        echo "0"
        return
    fi
    
    if ! date -d "$date2" &>/dev/null; then
        echo "0"
        return
    fi
    
    local d1=$(date -d "$date1" +%s 2>/dev/null)
    local d2=$(date -d "$date2" +%s 2>/dev/null)
    
    if [[ -z "$d1" ]] || [[ -z "$d2" ]]; then
        echo "0"
        return
    fi
    
    echo $(( (d1 - d2) / 86400 ))
}

# Function to get user creation date - NEW
get_user_creation_date() {
    local user="$1"
    local log_file="/var/log/create-shadowsocks.log"
    
    if [[ -f "$log_file" ]]; then
        local created=$(grep -E "SHADOWSOCKS ACCOUNT CREATED.*$user" "$log_file" 2>/dev/null | \
                       head -1 | awk '{print $1, $2}')
        if [[ -n "$created" ]]; then
            echo "$created"
        else
            echo "Unknown"
        fi
    else
        echo "Unknown"
    fi
}

# Main script
echo -e "${yellow}Loading Shadowsocks users...${nc}"
users=($(get_ss_users))

if [[ ${#users[@]} -eq 0 ]] || [[ -z "${users[0]}" ]]; then
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}      SHADOWSOCKS USER MONITOR         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${red}No Shadowsocks users found in configuration${nc}"
    echo -e "${yellow}Checking config file structure...${nc}"
    
    # Debug info
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${blue}Available inbound tags:${nc}"
        jq -r '.inbounds[]? | .tag' /usr/local/etc/xray/config.json 2>/dev/null || echo "Cannot read config"
        
        echo -e "${blue}Shadowsocks WS clients count:${nc}"
        jq '[.inbounds[] | select(.tag == "ss-ws") | .settings.clients[]?] | length' /usr/local/etc/xray/config.json 2>/dev/null || echo "0"
        
        echo -e "${blue}Shadowsocks gRPC clients count:${nc}"
        jq '[.inbounds[] | select(.tag == "ss-grpc") | .settings.clients[]?] | length' /usr/local/etc/xray/config.json 2>/dev/null || echo "0"
    else
        echo -e "${red}Config file not found${nc}"
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
    password="${user_details[0]}"
    method="${user_details[1]}"
    expiry="${user_details[2]}"
    services=$(get_user_services "$user")
    created=$(get_user_creation_date "$user")
    
    # Check if expired
    if [[ "$expiry" == "Not Set" ]]; then
        status="${red}NOT SET${nc}"
        days_text=""
    else
        days_left=$(date_diff "$expiry" "$today")
        if [[ $days_left -lt 0 ]]; then
            status="${red}EXPIRED${nc}"
            days_text="($((-$days_left)) days ago)"
        elif [[ $days_left -eq 0 ]]; then
            status="${yellow}TODAY${nc}"
            days_text="(0 days)"
        elif [[ $days_left -le 7 ]]; then
            status="${yellow}$days_left days${nc}"
            days_text=""
        else
            status="${green}$days_left days${nc}"
            days_text=""
        fi
    fi
    
    printf "  %-3s %-18s %-12s %-10s %-8s [%b] %s\n" "$((i+1))" "$user" "$expiry" "$method" "$services" "$status" "$days_text"
done

echo -e "${red}=========================================${nc}"
echo ""

# Check active connections
echo -e "${blue}ACTIVE & RECENT CONNECTIONS (last 15 minutes):${nc}"
echo -e "${red}=========================================${nc}"

active_users_count=0
total_connections=0

for user in "${users[@]}"; do
    active_ips=($(check_user_connections "$user"))
    
    if [[ ${#active_ips[@]} -gt 0 ]]; then
        ((active_users_count++))
        user_details=($(get_user_details "$user" | tr '|' ' '))
        method="${user_details[1]}"
        services=$(get_user_services "$user")
        
        echo -e "${green}✓ $user${nc}"
        echo -e "  └─ Method: ${blue}$method${nc} | Services: ${yellow}$services${nc}"
        
        for ip in "${active_ips[@]}"; do
            connection_count=$(count_connections_per_ip "$ip")
            location=$(get_ip_location "$ip")
            
            if [[ "$ip" == *"-RECENT" ]]; then
                # Recent connection (not currently active)
                ip_clean="${ip%-RECENT}"
                echo -e "     └─ ${yellow}IP: $ip_clean${nc} (recent)"
                echo -e "        └─ Location: ${blue}$location${nc}"
            else
                # Currently active connection
                ((total_connections += connection_count))
                echo -e "     └─ ${blue}IP: $ip${nc}"
                echo -e "        ├─ Connections: ${green}$connection_count${nc}"
                echo -e "        └─ Location: ${yellow}$location${nc}"
            fi
        done
        echo ""
    fi
done

if [[ $active_users_count -eq 0 ]]; then
    echo -e "${yellow}No active or recent connections found${nc}"
    echo -e "${yellow}Note: Checking connections from last 15 minutes${nc}"
fi

# Show Xray service logs summary
echo -e "${blue}XRAY SERVICE STATUS:${nc}"
echo -e "${red}=========================================${nc}"

if systemctl is-active --quiet xray; then
    echo -e "Xray: ${green}RUNNING ✓${nc}"
    
    # Show recent errors if any
    recent_errors=$(journalctl -u xray --since "15 minutes ago" 2>/dev/null | grep -i error | tail -3)
    if [[ -n "$recent_errors" ]]; then
        echo -e "${yellow}Recent errors:${nc}"
        echo "$recent_errors" | while read -r error; do
            echo -e "  └─ ${red}$error${nc}"
        done
    else
        echo -e "${green}No recent errors${nc}"
    fi
    
    # Show uptime
    uptime=$(systemctl show xray --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
    if [[ -n "$uptime" ]]; then
        echo -e "Uptime: ${blue}$uptime${nc}"
    fi
else
    echo -e "Xray: ${red}STOPPED ✗${nc}"
fi

# Nginx status
if systemctl is-active --quiet nginx; then
    echo -e "Nginx: ${green}RUNNING ✓${nc}"
else
    echo -e "Nginx: ${red}STOPPED ✗${nc}"
fi

echo -e "${red}=========================================${nc}"

# Summary
echo -e "${green}SUMMARY:${nc}"
echo -e "  Total Users: ${#users[@]}"
echo -e "  Active Users: $active_users_count"
echo -e "  Total Connections: $total_connections"
echo -e "  Monitoring Period: Last 15 minutes"

# Check expired users
expired_count=0
expiring_soon_count=0
for user in "${users[@]}"; do
    user_details=($(get_user_details "$user" | tr '|' ' '))
    expiry="${user_details[2]}"
    
    if [[ "$expiry" != "Not Set" ]]; then
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

# Disk usage for logs
echo -e "${blue}LOG INFORMATION:${nc}"
log_size=$(du -sh /var/log/xray/ 2>/dev/null | cut -f1)
echo -e "  Xray Logs Size: ${yellow}${log_size:-Unknown}${nc}"

echo -e "${red}=========================================${nc}"

# Quick health check
echo -e "${blue}QUICK HEALTH CHECK:${nc}"
if [[ -f "/usr/local/etc/xray/config.json" ]]; then
    if /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json &>/dev/null; then
        echo -e "  Config Test: ${green}PASSED ✓${nc}"
    else
        echo -e "  Config Test: ${red}FAILED ✗${nc}"
    fi
fi

# Check if ports are listening
if ss -tulpn | grep -q ":443 "; then
    echo -e "  Port 443: ${green}LISTENING ✓${nc}"
else
    echo -e "  Port 443: ${red}NOT LISTENING ✗${nc}"
fi

echo -e "${red}=========================================${nc}"

read -n 1 -s -r -p "Press any key to back on menu"
m-ssws
