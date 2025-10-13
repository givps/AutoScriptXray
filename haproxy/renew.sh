#!/bin/bash
# =========================================
# RENEW SSH USER - HAPROXY WEBSOCKET VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# Configuration
LOG_FILE="/var/log/user-renewal.log"

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}        RENEW SSH USER - HAProxy WS    ${nc}"
echo -e "${red}=========================================${nc}"

# Function to display user list
show_user_list() {
    echo -e "${yellow}📋 Active SSH Users:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read user; do
        if [ "$user" != "sync" ] && [ "$user" != "halt" ]; then
            expiry=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            if [ "$expiry" != "never" ]; then
                expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
                today_sec=$(date +%s)
                if [ $expiry_sec -ge $today_sec ]; then
                    days_left=$(( (expiry_sec - today_sec) / 86400 ))
                    if [ $days_left -le 7 ]; then
                        echo -e " ${red}• $user${nc} - ${red}$days_left day(s) left${nc}"
                    else
                        echo -e " ${white}• $user${nc} - ${green}$days_left day(s) left${nc}"
                    fi
                else
                    echo -e " ${red}• $user${nc} - ${red}EXPIRED${nc}"
                fi
            else
                echo -e " ${white}• $user${nc} - ${cyan}Never expires${nc}"
            fi
        fi
    done
    echo -e "${blue}=========================================${nc}"
    echo ""
}

# Show user list
show_user_list

# Input username
read -p "Username to renew : " User

# Check if user exists
if ! getent passwd "$User" >/dev/null 2>&1; then
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}            RENEW SSH USER             ${nc}"
    echo -e "${red}=========================================${nc}"  
    echo -e ""
    echo -e "   ${red}❌ Username '$User' Does Not Exist${nc}"
    echo -e ""
    echo -e "${yellow}💡 Available users:${nc}"
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | grep -v -E "^(sync|halt)" | head -10
    echo -e ""
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-sshovpn
    exit 1
fi

# Check if user is a system user
user_shell=$(getent passwd "$User" | cut -d: -f7)
if [ "$user_shell" != "/bin/false" ]; then
    echo -e "${yellow}⚠️  Warning: User '$User' is not an SSH user (shell: $user_shell)${nc}"
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Operation cancelled.${nc}"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-sshovpn
        exit 0
    fi
fi

# Get current user info
current_expiry=$(chage -l "$User" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
user_id=$(id -u "$User")
user_home=$(getent passwd "$User" | cut -d: -f6)

# Display current user info
echo -e "${blue}👤 User Information:${nc}"
echo -e "  Username : ${cyan}$User${nc}"
echo -e "  User ID  : ${white}$user_id${nc}"
echo -e "  Home Dir : ${white}$user_home${nc}"
echo -e "  Current  : ${yellow}$current_expiry${nc}"
echo ""

# Input day with validation
while true; do
    read -p "Days to extend [1-365]: " day
    if [[ "$day" =~ ^[0-9]+$ ]] && [ "$day" -ge 1 ] && [ "$day" -le 365 ]; then
        break
    else
        echo -e "${red}❌ Invalid input. Please enter a number between 1-365.${nc}"
    fi
done

# Calculate expiration
Today=$(date +%s)
day_Detailed=$((day * 86400))

# Handle different current expiry scenarios
if [ "$current_expiry" = "never" ]; then
    # If never expires, set from today
    Expire_On=$((Today + day_Detailed))
    expiry_note="(set from never expire)"
elif [ "$current_expiry" = "password must be changed" ] || [ "$current_expiry" = "account must be changed" ]; then
    # If special status, set from today
    Expire_On=$((Today + day_Detailed))
    expiry_note="(previously: $current_expiry)"
else
    # Parse current expiry
    current_expiry_sec=$(date -d "$current_expiry" +%s 2>/dev/null)
    if [ $? -eq 0 ] && [ $current_expiry_sec -gt $Today ]; then
        # Extend from current expiry
        Expire_On=$((current_expiry_sec + day_Detailed))
        expiry_note="(extended from current)"
    else
        # Current expiry is invalid or expired, set from today
        Expire_On=$((Today + day_Detailed))
        expiry_note="(set from today - was expired/invalid)"
    fi
fi

# Format for system (YYYY-MM-DD) and display
Expiration=$(date -u --date="1970-01-01 $Expire_On sec GMT" +%Y-%m-%d)
Expiration_Display=$(date -u --date="1970-01-01 $Expire_On sec GMT" '+%d %b %Y')
Today_Display=$(date '+%d %b %Y')

# Renew user account
echo -e "${yellow}🔄 Renewing user account...${nc}"

# Unlock account if locked
passwd -u "$User" 2>/dev/null

# Set new expiration
if usermod -e "$Expiration" "$User" 2>/dev/null; then
    # Verify the change
    verified_expiry=$(chage -l "$User" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
    
    clear
    
    # Display results
    echo -e "${red}=========================================${nc}"
    echo -e "${green}        SSH USER RENEWED SUCCESSFULLY  ${nc}"
    echo -e "${red}=========================================${nc}"  
    echo -e ""
    echo -e " ${blue}👤 User Information:${nc}"
    echo -e " Username        : ${cyan}$User${nc}"
    echo -e " User ID         : ${white}$user_id${nc}"
    echo -e " Renewal Date    : ${white}$Today_Display${nc}"
    echo -e ""
    echo -e " ${green}🔄 Renewal Details:${nc}"
    echo -e " Days Added      : ${green}$day day(s)${nc}"
    echo -e " Previous Expiry : ${yellow}$current_expiry${nc}"
    echo -e " New Expiry      : ${green}$Expiration_Display${nc}"
    echo -e " Status          : ${green}$expiry_note${nc}"
    echo -e ""
    echo -e " ${blue}🔧 Service Access:${nc}"
    echo -e " SSH Access      : ${green}✅ ACTIVE${nc}"
    echo -e " WebSocket Access: ${green}✅ ACTIVE${nc}"
    echo -e " Account Status  : ${green}✅ UNLOCKED${nc}"
    echo -e ""
    echo -e "${red}=========================================${nc}"
    
    # Log the renewal
    echo "$(date '+%Y-%m-%d %H:%M:%S') - RENEWED: $User for $day days (From: $current_expiry To: $Expiration_Display)" >> "$LOG_FILE"
    
else
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${red}         RENEWAL FAILED                ${nc}"
    echo -e "${red}=========================================${nc}"  
    echo -e ""
    echo -e " ${red}❌ Failed to renew user: $User${nc}"
    echo -e ""
    echo -e " ${yellow}Possible reasons:${nc}"
    echo -e " • User account is locked or disabled"
    echo -e " • System error"
    echo -e " • Permission denied"
    echo -e ""
    echo -e "${red}=========================================${nc}"
    
    # Log the failure
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FAILED: Renew $User for $day days" >> "$LOG_FILE"
fi

# Show renewal history
echo -e ""
echo -e "${yellow}📜 Recent Renewals:${nc}"
echo -e "${blue}=========================================${nc}"
tail -5 "$LOG_FILE" 2>/dev/null || echo "No renewal history found"
echo -e "${blue}=========================================${nc}"

echo -e ""
read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn