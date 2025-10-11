#!/bin/bash
# =========================================
# AUTO KICK SSH USER
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

clear

# Configuration
MAX=${1:-2}  # Default 2 connections, can be overridden

# Detect OS and log file
if [ -e "/var/log/auth.log" ]; then
    OS=1
    LOG="/var/log/auth.log"
elif [ -e "/var/log/secure" ]; then
    OS=2
    LOG="/var/log/secure"
else
    echo -e "${red}Error: No auth log file found${nc}"
    exit 1
fi

echo -e "${blue}=== AUTO KICK SSH USER ===${nc}"
echo -e "Max connections per user: ${yellow}$MAX${nc}"
echo

# Get all users with home directories
mapfile -t username < <(getent passwd | grep "/home/" | cut -d: -f1)

declare -A user_connections
declare -A user_pids

# Initialize counters
for user in "${username[@]}"; do
    user_connections["$user"]=0
    user_pids["$user"]=""
done

# Function to count connections
count_connections() {
    local service=$1
    local log_pattern=$2
    local pid_extract=$3
    local user_extract=$4
    local ip_extract=$5
    
    # Get current processes
    if [ "$service" == "dropbear" ]; then
        mapfile -t proc < <(ps aux | grep -i dropbear | grep -v grep | awk '{print $2}')
    else
        mapfile -t proc < <(ps aux | grep "sshd.*@" | grep -v grep | awk '{print $2}')
    fi
    
    # Analyze log for each PID
    for PID in "${proc[@]}"; do
        if grep -q "\[$PID\]" "$LOG" 2>/dev/null; then
            local log_entry=$(grep "\[$PID\]" "$LOG" | grep -i "$log_pattern" | tail -1)
            if [ -n "$log_entry" ]; then
                local user=$(echo "$log_entry" | awk "$user_extract" | sed "s/'//g")
                local ip=$(echo "$log_entry" | awk "$ip_extract")
                
                # Check if user exists in our list
                if [[ " ${username[@]} " =~ " ${user} " ]]; then
                    ((user_connections["$user"]++))
                    user_pids["$user"]+=" $PID"
                    
                    echo -e "  Found: ${cyan}$user${nc} from ${yellow}$ip${nc} (PID: $PID)"
                fi
            fi
        fi
    done
}

# Count Dropbear connections
echo -e "${blue}Checking Dropbear connections...${nc}"
count_connections "dropbear" "Password auth succeeded" '{print $10}' '{print $12}'

# Count SSH connections
echo -e "${blue}Checking SSH connections...${nc}"
count_connections "sshd" "Accepted password for" '{print $9}' '{print $11}'

# Kick users exceeding limit
echo
echo -e "${blue}Checking for users exceeding limit...${nc}"
kicked_count=0

for user in "${username[@]}"; do
    connections=${user_connections["$user"]}
    if [ "$connections" -gt "$MAX" ]; then
        echo -e "${red}Kicking $user: $connections connections (max: $MAX)${nc}"
        
        # Log the action
        echo "$(date '+%Y-%m-%d %X') - $user - $connections connections" >> /root/log-limit.txt
        
        # Kill user's processes
        if [ -n "${user_pids[$user]}" ]; then
            for pid in ${user_pids[$user]}; do
                if ps -p "$pid" > /dev/null 2>&1; then
                    kill "$pid"
                    echo -e "  Killed PID: $pid"
                fi
            done
        fi
        
        ((kicked_count++))
    elif [ "$connections" -gt 0 ]; then
        echo -e "${green}$user: $connections connections ✓${nc}"
    fi
done

# Summary
echo
if [ "$kicked_count" -gt 0 ]; then
    echo -e "${red}Kicked $kicked_count users for exceeding connection limit${nc}"
else
    echo -e "${green}No users exceeded connection limit${nc}"
fi

echo -e "${blue}=== Auto kick completed ===${nc}"
