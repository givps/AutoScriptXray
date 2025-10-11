#!/bin/bash
# =========================================
# CHECK MULTI SSH USER
# =========================================

# color
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}         CEK USER MULTI SSH        ${nc}"
echo -e "${red}=========================================${nc}"

# Function to display violation logs
display_violations() {
    if [ -e "/root/log-limit.txt" ]; then
        echo -e "${white}User Who Violate The Maximum Limit${nc}"
        echo -e "${white}Time - Username - Number of Multilogin${nc}"
        echo -e "${red}=========================================${nc}"
        cat /root/log-limit.txt
    else
        echo -e "${yellow} No user has committed a violation${nc}"
        echo -e "${yellow} or${nc}"
        echo -e "${yellow} The user-limit script not been executed.${nc}"
    fi
}

# Display current violations
display_violations

echo ""
echo -e "${red}=========================================${nc}"
echo -e "${blue}              MENU OPTIONS              ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Refresh Check"
echo -e "${white}2${nc} Clear Log History"
echo -e "${white}3${nc} Back to SSH Menu"
echo -e "${white}4${nc} Back to SSH Menu"
echo -e "${white}5${nc} Exit"
echo -e "${red}=========================================${nc}"
echo ""

read -p "Select option [1-4]: " option

case $option in
    1)
        echo -e "${green}Refreshing...${nc}"
        sleep 1
        # Run script again to refresh
        exec $0
        ;;
    2)
        if [ -e "/root/log-limit.txt" ]; then
            rm -f /root/log-limit.txt
            echo -e "${green}Log history cleared successfully!${nc}"
            sleep 2
            exec $0
        else
            echo -e "${yellow}No log file to clear${nc}"
            sleep 2
            exec $0
        fi
        ;;
    3)
        echo -e "${green}Returning to SSH Menu...${nc}"
        sleep 1
        m-sshovpn
        ;;
    4)
        echo -e "${green}Returning to SSH Menu...${nc}"
        sleep 1
        cleanup
        m-sshovpn
        ;;
    5)
        echo -e "${green}Exiting...${nc}"
        sleep 1
        clear
        exit 0
        ;;
    *)
        echo -e "${red}Invalid option! Returning to SSH Menu...${nc}"
        sleep 2
        m-sshovpn
        ;;
esac
