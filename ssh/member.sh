#!/bin/bash
# =========================================
# MEMBER SSH USERS
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

echo -e "${red}=========================================${nc}"
echo -e "${blue}              SSH USER LIST              ${nc}"
echo -e "${red}=========================================${nc}"      
echo -e "USERNAME          EXP DATE          STATUS"
echo -e "${red}=========================================${nc}"

# Counters
total_users=0
active_users=0
locked_users=0
expired_users=0

# Get today's date for comparison
today_epoch=$(date +%s)

# Process users more efficiently
while IFS=: read -r username _ uid _ _ _ _; do
    # Skip system users and nobody
    if [[ $uid -ge 1000 ]] && [[ $username != "nobody" ]]; then
        ((total_users++))
        
        # Get account status
        if status_info=$(passwd -S "$username" 2>/dev/null); then
            status=$(echo "$status_info" | awk '{print $2}')
        else
            status="U" # Unknown
        fi
        
        # Get expiration date
        expire_info=$(chage -l "$username" 2>/dev/null | grep "Account expires")
        if echo "$expire_info" | grep -q "never"; then
            expire_date="never"
            expire_display="never          "
            is_expired=0
        else
            expire_date=$(echo "$expire_info" | awk -F": " '{print $2}')
            if [[ -n "$expire_date" ]]; then
                expire_epoch=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
                expire_display=$(date -d "$expire_date" "+%d %b %Y" 2>/dev/null || echo "invalid date")
                
                if [[ $expire_epoch -lt $today_epoch ]]; then
                    is_expired=1
                    ((expired_users++))
                else
                    is_expired=0
                fi
            else
                expire_display="unknown       "
                is_expired=0
            fi
        fi
        
        # Determine status and color
        if [[ "$status" == "L" ]]; then
            status_color="${red}"
            status_text="LOCKED"
            ((locked_users++))
        elif [[ $is_expired -eq 1 ]]; then
            status_color="${yellow}"
            status_text="EXPIRED"
        else
            status_color="${green}"
            status_text="ACTIVE"
            ((active_users++))
        fi
        
        # Display user info
        printf "%-17s %-17s ${status_color}%s${nc}\n" "$username" "$expire_display" "$status_text"
    fi
done < /etc/passwd

echo -e "${red}=========================================${nc}"
echo -e "Total Users    : ${cyan}$total_users${nc}"
echo -e "Active Users   : ${green}$active_users${nc}"
echo -e "Locked Users   : ${red}$locked_users${nc}"
echo -e "Expired Users  : ${yellow}$expired_users${nc}"
echo -e "${red}=========================================${nc}"

read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
