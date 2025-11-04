#!/bin/bash
# ==========================================
# VPS Management Menu - Xray & SSL
# ==========================================

# Initialize with error handling
set -euo pipefail

# Color definitions
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
cyan='\e[1;36m'
nc='\e[0m'

# Function to get IP with fallbacks
get_ip() {
    ip=$(curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || \
         wget -qO- --timeout=5 ipv4.icanhazip.com 2>/dev/null || \
         echo "Unknown")
    echo "$ip"
}

# Function to get domain safely
get_domain() {
    if [[ -f "/usr/local/etc/xray/domain" ]] && [[ -r "/usr/local/etc/xray/domain" ]]; then
        domain=$(cat /usr/local/etc/xray/domain 2>/dev/null | head -n1)
    elif [[ -f "/root/domain" ]] && [[ -r "/root/domain" ]]; then
        domain=$(cat /root/domain 2>/dev/null | head -n1)
    else
        domain="Not Configured"
    fi
    echo "$domain"
}

# Function to check certificate status
check_cert_status() {
    local domain=$1
    local cert_file="$HOME/.acme.sh/${domain}_ecc/${domain}.key"
    
    if [[ ! -f "$cert_file" ]]; then
        echo "Not Found"
        return
    fi
    
    # More reliable certificate check
    if modifyTime=$(stat -c %y "$cert_file" 2>/dev/null); then
        modifyTime1=$(date +%s -d "$modifyTime")
        currentTime=$(date +%s)
        stampDiff=$((currentTime - modifyTime1))
        days=$((stampDiff / 86400))
        remainingDays=$((90 - days))
        
        if [[ $remainingDays -le 0 ]]; then
            echo "expired"
        else
            echo "${remainingDays} days"
        fi
    else
        echo "Unknown"
    fi
}

# Function to get CPU usage accurately
get_cpu_usage() {
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')
    echo "$cpu_usage"
}

# Function to display header
display_header() {
    clear
    # Get all system information
    MYIP=$(get_ip)
    domain=$(get_domain)
    tlsStatus=$(check_cert_status "$domain")
    country=$(cat /myinfo/country 2>/dev/null || echo "API limit..." 2>/dev/null)
    uptime=$(uptime -p | cut -d " " -f 2-10)
    DATE2=$(date -R | cut -d " " -f -5)
    cpu_usage=$(get_cpu_usage)
    
    # Memory information
    tram=$(free -m | awk 'NR==2 {print $2}')
    uram=$(free -m | awk 'NR==2 {print $3}')
    fram=$(free -m | awk 'NR==2 {print $4}')
    
    # OS information
    os_info=$(hostnamectl | grep "Operating System" | cut -d ' ' -f5-)
    
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}                      VPS INFO                    ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${white} OS            ${nc}: $os_info"
    echo -e "${white} Uptime        ${nc}: $uptime"
    echo -e "${white} IP            ${nc}: $MYIP"
    echo -e "${white} Country       ${nc}: $country"
    echo -e "${white} DOMAIN        ${nc}: $domain"
    echo -e "${white} TLS Status    ${nc}: $tlsStatus"
    echo -e "${white} CPU Usage     ${nc}: $cpu_usage"
    echo -e "${white} DATE & TIME   ${nc}: $DATE2"
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}                      RAM INFO                    ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e ""
    echo -e "${white} RAM USED     ${nc}: $uram MB"
    echo -e "${white} RAM FREE     ${nc}: $fram MB"	
    echo -e "${white} RAM TOTAL    ${nc}: $tram MB"
    echo -e "${white} USAGE        ${nc}: $((uram * 100 / tram))%"
    echo -e ""
}

# Function to display menu
display_menu() {
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}                       MENU                       ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e ""
    echo -e "${white} 1 ${nc}  : Menu SSH"
    echo -e "${white} 2 ${nc}  : Menu Vmess"
    echo -e "${white} 3 ${nc}  : Menu Vless"
    echo -e "${white} 4 ${nc}  : Menu Trojan"
    echo -e "${white} 5 ${nc}  : Menu Setting"
    echo -e "${white} 6 ${nc}  : Menu TOR"
    echo -e "${white} 7 ${nc}  : Xray Log"
    echo -e "${white} 8 ${nc}  : Status Service"
    echo -e "${white} 9 ${nc}  : Clear RAM Cache"
    echo -e "${white} 10 ${nc} : Reboot VPS"
    echo -e "${white} x ${nc}  : Exit Script"
    echo -e ""
    echo -e "${red}=========================================${nc}"
    echo -e "${white} Client Name ${nc}: VIP-MEMBERS"
    echo -e "${white} Expired     ${nc}: Lifetime"
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         t.me/givps_com ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e ""
}

# Function to clear RAM cache safely
clear_ram_cache() {
    echo -e "${yellow}Clearing RAM cache...${nc}"
    sync
    echo 3 > /proc/sys/vm/drop_caches
    sleep 2
    echo -e "${green}RAM cache cleared successfully!${nc}"
    sleep 2
}

# Function to reboot system safely
safe_reboot() {
    echo -e "${yellow}Rebooting system...${nc}"
    echo -e "${yellow}Please wait...${nc}"
    sleep 3
    /sbin/reboot
}

# Function to handle invalid input
handle_invalid_input() {
    echo -e "${red}Invalid option! Please select a valid menu option.${nc}"
    sleep 2
}

# Main menu function
main_menu() {
    while true; do
        display_header
        display_menu
        
        read -p " Select menu [1-10, x]: " opt
        
        case $opt in
            1) clear ; m-sshovpn ;;
            2) clear ; m-vmess ;;
            3) clear ; m-vless ;;
            4) clear ; m-trojan ;;
            5) clear ; m-system ;;
            6) clear ; m-tor ;;
            7) clear ; xray-log ;;
            8) clear ; running ;;
            9) clear ; clear_ram_cache ;;
            10) clear ; safe_reboot ;;
            x|X) 
                echo -e "${green}Goodbye! To restart the menu use: menu${nc}"
                exit 0 
                ;;
            *) 
                handle_invalid_input 
                ;;
        esac
        
        # After executing any command (except exit), ask to continue
        if [[ $opt != "x" ]] && [[ $opt != "X" ]]; then
            echo ""
            read -p "Press Enter to return to main menu..."
        fi
    done
}

# Check if required commands are available
check_dependencies() {
    local missing_deps=()
    
    for cmd in wget curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${red}Missing dependencies: ${missing_deps[*]}${nc}"
        echo -e "${yellow}Please install them first.${nc}"
        exit 1
    fi
}

# Main execution
main() {
    # Check dependencies
    check_dependencies
    
    # Trap Ctrl+C for graceful exit
    trap 'echo -e "\n${yellow}Interrupted. Use Ctrl+D or type exit to quit properly.${nc}"; sleep 1' SIGINT
    
    # Start main menu
    main_menu
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
