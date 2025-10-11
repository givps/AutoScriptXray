#!/bin/bash
# =========================================
# Bandwidth Monitor Menu
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
purple='\e[1;35m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# ==========================================
# Getting system info
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# Function to check if vnstat is installed
check_vnstat() {
    if ! command -v vnstat &> /dev/null; then
        echo -e "${red}ERROR: vnstat is not installed!${nc}"
        echo -e "${yellow}Please install vnstat first:${nc}"
        echo -e "  apt update && apt install vnstat -y"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        m-system
        exit 1
    fi
}

# Function to check vnstat database
check_vnstat_db() {
    if ! vnstat --version &> /dev/null; then
        echo -e "${yellow}Setting up vnstat database...${nc}"
        systemctl enable vnstat
        systemctl start vnstat
        sleep 2
    fi
}

# Function to display system info
show_system_info() {
    echo -e "${cyan}Server IP: $MYIP${nc}"
    if [[ -n "$domain" ]]; then
        echo -e "${cyan}Domain: $domain${nc}"
    fi
    echo -e "${cyan}Date: $(date)${nc}"
    echo ""
}

# Main menu
clear
check_vnstat
check_vnstat_db

echo -e "${blue}=========================================${nc}"
echo -e "${blue}            BANDWIDTH MONITOR           ${nc}"
echo -e "${blue}=========================================${nc}"
echo ""
show_system_info
echo -e "${purple} 1 ${nc} View Total Remaining Bandwidth"
echo -e "${purple} 2 ${nc} Usage Table Every 5 Minutes"
echo -e "${purple} 3 ${nc} Hourly Usage Table"
echo -e "${purple} 4 ${nc} Daily Usage Table"
echo -e "${purple} 5 ${nc} Monthly Usage Table"
echo -e "${purple} 6 ${nc} Annual Usage Table"
echo -e "${purple} 7 ${nc} Highest Usage Table"
echo -e "${purple} 8 ${nc} Hourly Usage Statistics"
echo -e "${purple} 9 ${nc} View Current Active Usage"
echo -e "${purple}10 ${nc} View Current Active Usage Traffic [5s]"
echo -e "${purple}11 ${nc} Real-time Bandwidth Monitor"
echo -e "${purple}12 ${nc} Interface-specific Statistics"
echo "" 
echo -e "${green} 0 ${nc} Back To Menu"
echo -e "${red} x ${nc} Exit"
echo "" 
echo -e "${blue}=========================================${nc}"
echo -e "${yellow}Note: Make sure vnstat is properly configured${nc}"
echo -e "${blue}=========================================${nc}"
echo ""
read -p " Select menu : " opt
echo ""

case $opt in
    1)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}      TOTAL SERVER BANDWIDTH REMAINING   ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    2)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}       TOTAL BANDWIDTH EVERY 5 MINUTES   ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -5
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    3)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}          TOTAL HOURLY BANDWIDTH         ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -h
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    4)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}           TOTAL DAILY BANDWIDTH         ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -d
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    5)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}          TOTAL MONTHLY BANDWIDTH        ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -m
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    6)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}           TOTAL YEARLY BANDWIDTH        ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -y
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    7)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}         HIGHEST TOTAL BANDWIDTH         ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -t
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    8)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}        HOURLY USAGE STATISTICS          ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -hg
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    9)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}        CURRENT LIVE BANDWIDTH           ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo -e "${yellow}Press [Ctrl+C] to exit${nc}"
        echo ""
        
        vnstat -l
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    10)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}      LIVE TRAFFIC BANDWIDTH [5s]        ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        vnstat -tr
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    11)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}      REAL-TIME BANDWIDTH MONITOR        ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo -e "${yellow}Press [Ctrl+C] to exit${nc}"
        echo ""
        
        # Real-time monitoring with iftop (if available)
        if command -v iftop &> /dev/null; then
            iftop
        else
            echo -e "${yellow}iftop not installed. Using vnstat live mode instead.${nc}"
            echo -e "${yellow}To install iftop: apt install iftop -y${nc}"
            echo ""
            vnstat -l
        fi
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    12)
        clear 
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}      INTERFACE-SPECIFIC STATISTICS      ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        
        # Show available interfaces
        echo -e "${cyan}Available network interfaces:${nc}"
        vnstat --iflist
        
        echo ""
        read -p "Enter interface name (e.g., eth0): " interface
        
        if [[ -n "$interface" ]]; then
            echo ""
            echo -e "${green}Statistics for interface: $interface${nc}"
            echo -e "${blue}=========================================${nc}"
            vnstat -i "$interface"
        else
            echo -e "${red}No interface specified${nc}"
        fi
        
        echo ""
        echo -e "${blue}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        bw
        ;;

    0)
        sleep 1
        m-system
        ;;

    [xX])
        echo -e "${yellow}Exiting...${nc}"
        exit 0
        ;;

    *)
        echo -e "${red}Invalid option!${nc}"
        sleep 1
        bw
        ;;
esac

