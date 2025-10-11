#!/bin/bash
# =========================================
# SSH AUTOKILL MENU
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
AUTOKILL_SCRIPT="/usr/bin/autokick"  # Configurable path

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}             AUTOKILL SSH MENU          ${nc}"
echo -e "${red}=========================================${nc}"

# Check status with better detection
if [ -f "/etc/cron.d/autokick" ] && grep -q -E "^# Autokill" "/etc/cron.d/autokick" 2>/dev/null; then
    echo -e "Status Autokill   : ${green}[ACTIVE]${nc}"
    
    # Show current settings
    cron_line=$(grep -E "^\*/[0-9]+" /etc/cron.d/autokick | head -1)
    if [[ $cron_line =~ \*/[0-9]+\ \*\ \*\ \*\ \*\ root\ $AUTOKILL_SCRIPT\ ([0-9]+) ]]; then
        interval=${cron_line#*/}
        interval=${interval%% *}
        max_conn=${BASH_REMATCH[1]}
        echo -e "Check Interval    : ${yellow}Every $interval minutes${nc}"
        echo -e "Max Connections   : ${yellow}$max_conn${nc}"
    fi
else
    echo -e "Status Autokill   : ${red}[INACTIVE]${nc}"
fi

echo -e ""
echo -e "${white}1${nc} AutoKill Every 5 Minutes"
echo -e "${white}2${nc} AutoKill Every 10 Minutes"
echo -e "${white}3${nc} AutoKill Every 15 Minutes"
echo -e "${white}4${nc} AutoKill Every 30 Minutes"
echo -e "${white}5${nc} Custom Interval"
echo -e "${white}6${nc} Turn Off AutoKill"
echo -e "${white}0${nc} Back to SSH Menu"
echo -e "${white}x${nc} Exit"
echo -e ""
echo -e "${red}=========================================${nc}"
echo -e ""

read -p "Select option [0-6 or x]: " AutoKill

# Validate autokill script exists
if [[ "$AutoKill" =~ ^[1-5]$ ]] && [ ! -f "$AUTOKILL_SCRIPT" ]; then
    echo -e "${red}Error: Autokill script not found at $AUTOKILL_SCRIPT${nc}"
    echo -e "${yellow}Please ensure the autokill script is installed.${nc}"
    read -n 1 -s -r -p "Press any key to continue..."
    $0
    exit 1
fi

case $AutoKill in
    1|2|3)
        case $AutoKill in
            1) interval=5 ;;
            2) interval=10 ;;
            3) interval=15 ;;
        esac
        
        while true; do
            read -p "Max connections allowed [1-10]: " max
            if [[ "$max" =~ ^[1-9]$|^10$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-10${nc}"
            fi
        done
        
        # Create cron entry safely
        cat > /etc/cron.d/autokick << EOF
# Autokill - Do not edit manually
# Check every $interval minutes, max $max connections
*/$interval * * * * root $AUTOKILL_SCRIPT $max
EOF
        
        echo -e "${green}✓ AutoKill activated${nc}"
        echo -e "  Check interval : Every $interval minutes"
        echo -e "  Max connections: $max"
        ;;
        
    4)
        while true; do
            read -p "Max connections allowed [1-10]: " max
            if [[ "$max" =~ ^[1-9]$|^10$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-10${nc}"
            fi
        done
        
        cat > /etc/cron.d/autokick << EOF
# Autokill - Do not edit manually
# Check every 30 minutes, max $max connections
*/30 * * * * root $AUTOKILL_SCRIPT $max
EOF
        
        echo -e "${green}✓ AutoKill activated${nc}"
        echo -e "  Check interval : Every 30 minutes"
        echo -e "  Max connections: $max"
        ;;
        
    5)
        while true; do
            read -p "Check interval in minutes [1-60]: " interval
            if [[ "$interval" =~ ^[1-9]$|^[1-5][0-9]$|^60$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-60${nc}"
            fi
        done
        
        while true; do
            read -p "Max connections allowed [1-10]: " max
            if [[ "$max" =~ ^[1-9]$|^10$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-10${nc}"
            fi
        done
        
        cat > /etc/cron.d/autokick << EOF
# Autokill - Do not edit manually
# Check every $interval minutes, max $max connections
*/$interval * * * * root $AUTOKILL_SCRIPT $max
EOF
        
        echo -e "${green}✓ AutoKill activated${nc}"
        echo -e "  Check interval : Every $interval minutes"
        echo -e "  Max connections: $max"
        ;;
        
    6)
        if [ -f "/etc/cron.d/autokick" ]; then
            rm -f /etc/cron.d/autokick
            echo -e "${yellow}✓ AutoKill disabled${nc}"
        else
            echo -e "${yellow}AutoKill was already inactive${nc}"
        fi
        ;;
        
    0)
        echo -e "${green}Returning to SSH Menu...${nc}"
        sleep 1
        m-sshovpn
        exit 0
        ;;
        
    x)
        clear
        exit 0
        ;;
        
    *)
        echo -e "${red}Invalid option!${nc}"
        sleep 2
        $0
        ;;
esac

# Reload cron configuration
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload cron >/dev/null 2>&1 || systemctl reload crond >/dev/null 2>&1
else
    service cron reload >/dev/null 2>&1 || service crond reload >/dev/null 2>&1
fi

echo ""
read -n 1 -s -r -p "Press any key to return to AutoKill menu..."
$0
