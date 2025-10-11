#!/bin/bash
# =========================================
# RENEW SSH USER
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
echo -e "${blue}            RENEW SSH USER             ${nc}"
echo -e "${red}=========================================${nc}"  
echo

# Input username
read -p "Username : " User

# Check if user exists
if ! egrep "^$User" /etc/passwd >/dev/null; then
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}            RENEW SSH USER             ${nc}"
    echo -e "${red}=========================================${nc}"  
    echo -e ""
    echo -e "   ${red}Username Does Not Exist${nc}"
    echo -e ""
    echo -e "${red}=========================================${nc}"
    read -n 1 -s -r -p "Press any key to back on menu"
    m-sshovpn
    exit 1
fi

# Input day with validation
while true; do
    read -p "Day Extend : " day
    if [[ "$day" =~ ^[0-9]+$ ]] && [ "$day" -gt 0 ]; then
        break
    else
        echo -e "${red}Invalid input. Please enter a positive number.${nc}"
    fi
done

# Calculate expiration
Today=$(date +%s)
day_Detailed=$((day * 86400))
Expire_On=$((Today + day_Detailed))

# Format for system (YYYY-MM-DD) and display
Expiration=$(date -u --date="1970-01-01 $Expire_On sec GMT" +%Y-%m-%d)
Expiration_Display=$(date -u --date="1970-01-01 $Expire_On sec GMT" '+%d %b %Y')

# Get current expiry for comparison
Current_Expiry=$(chage -l "$User" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')

# Renew user account
passwd -u "$User" 2>/dev/null
usermod -e "$Expiration" "$User"

clear

# Display results
echo -e "${red}=========================================${nc}"
echo -e "${blue}            SSH USER RENEWED           ${nc}"
echo -e "${red}=========================================${nc}"  
echo -e ""
echo -e " Username    : $User"
echo -e " Day Added  : $day day"
echo -e " Expires on  : $Expiration_Display"
echo -e ""
echo -e "Previous expiry: $Current_Expiry"
echo -e ""
echo -e "Account successfully renewed"
echo -e ""
echo -e "${red}=========================================${nc}"

read -n 1 -s -r -p "Press any key to back on menu"
m-sshovpn
