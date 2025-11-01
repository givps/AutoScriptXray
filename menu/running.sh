#!/bin/bash
# =========================================
# SYSTEM STATUS INFORMATION
# =========================================

# ---------- Colors ----------
RED='\e[1;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
CYAN='\e[1;36m'
WHITE='\e[1;37m'
NC='\e[0m'

# Function to get IP address
get_ip() {
    curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null || \
    wget -qO- --timeout=5 ipv4.icanhazip.com 2>/dev/null || \
    echo "Unknown"
}

# Function to get domain
get_domain() {
    if [[ -f "/etc/xray/domain" ]] && [[ -r "/etc/xray/domain" ]]; then
        cat /etc/xray/domain 2>/dev/null | head -n1
    elif [[ -f "/usr/local/etc/xray/domain" ]] && [[ -r "/usr/local/etc/xray/domain" ]]; then
        cat /usr/local/etc/xray/domain 2>/dev/null | head -n1
    elif [[ -f "/root/domain" ]] && [[ -r "/root/domain" ]]; then
        cat /root/domain 2>/dev/null | head -n1
    else
        echo "Not Configured"
    fi
}

# Function to check service status
check_service_status() {
    local service_name=$1
    local service_type=$2
    
    case $service_type in
        "systemctl")
            if systemctl is-active --quiet "$service_name"; then
                echo -e "${GREEN}Running ${NC}(No Error)"
            else
                echo -e "${RED}Not Running ${NC}(Error)"
            fi
            ;;
        "init.d")
            if /etc/init.d/"$service_name" status | grep -q "running"; then
                echo -e "${GREEN}Running ${NC}(No Error)"
            else
                echo -e "${RED}Not Running ${NC}(Error)"
            fi
            ;;
        "process")
            if pgrep -x "$service_name" > /dev/null; then
                echo -e "${GREEN}Running ${NC}(No Error)"
            else
                echo -e "${RED}Not Running ${NC}(Error)"
            fi
            ;;
    esac
}

# Function to get system information
get_system_info() {
    # OS Information
    source /etc/os-release
    local os_name=$NAME
    local os_version=$VERSION_ID
    
    # Memory Information
    local total_ram=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
    local used_ram=$(grep "MemAvailable:" /proc/meminfo | awk '{print $2}')
    total_ram=$((total_ram / 1024))
    used_ram=$((used_ram / 1024))
    local free_ram=$((total_ram - used_ram))
    local ram_usage=$((used_ram * 100 / total_ram))
    
    # CPU Information
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')
    local cpu_cores=$(nproc)
    
    # Disk Information
    local disk_usage=$(df -h / | awk 'NR==2{print $5}')
    local disk_free=$(df -h / | awk 'NR==2{print $4}')
    
    # Uptime
    local uptime=$(uptime -p | sed 's/up //')
    
    # Kernel Version
    local kernel_version=$(uname -r)
    
    echo "$os_name" "$os_version" "$total_ram" "$free_ram" "$ram_usage" "$cpu_usage" "$cpu_cores" "$disk_usage" "$disk_free" "$uptime" "$kernel_version"
}

# Function to get network statistics
get_network_stats() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    local rx_bytes=$(cat /sys/class/net/"$interface"/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx_bytes=$(cat /sys/class/net/"$interface"/statistics/tx_bytes 2>/dev/null || echo 0)
    
    # Convert to human readable format
    local rx_human=$(numfmt --to=iec "$rx_bytes")
    local tx_human=$(numfmt --to=iec "$tx_bytes")
    
    echo "$interface" "$rx_human" "$tx_human"
}

# Function to display header
display_header() {
    clear
    echo -e "${RED}=========================================${NC}"
    echo -e "${BLUE}             SYSTEM INFORMATION               ${NC}"
    echo -e "${RED}=========================================${NC}"
}

# Function to display system information
display_system_info() {
    # Get all system information
    read -r os_name os_version total_ram free_ram ram_usage cpu_usage cpu_cores disk_usage disk_free uptime kernel_version <<< "$(get_system_info)"
    
    # Get network stats
    read -r interface rx_bytes tx_bytes <<< "$(get_network_stats)"
    
    # Get IP and domain
    local public_ip=$(get_ip)
    local domain=$(get_domain)
    
    echo -e "${WHITE} Hostname     ${NC}: $HOSTNAME"
    echo -e "${WHITE} OS Name      ${NC}: $os_name"
    echo -e "${WHITE} OS Version   ${NC}: $os_version"
    echo -e "${WHITE} Kernel       ${NC}: $kernel_version"
    echo -e "${WHITE} Uptime       ${NC}: $uptime"
    echo -e "${WHITE} CPU Cores    ${NC}: $cpu_cores"
    echo -e "${WHITE} CPU Usage    ${NC}: $cpu_usage"
    echo -e "${WHITE} Total RAM    ${NC}: ${total_ram} MB"
    echo -e "${WHITE} Free RAM     ${NC}: ${free_ram} MB"
    echo -e "${WHITE} RAM Usage    ${NC}: ${ram_usage}%"
    echo -e "${WHITE} Disk Usage   ${NC}: $disk_usage"
    echo -e "${WHITE} Disk Free    ${NC}: $disk_free"
    echo -e "${WHITE} Public IP    ${NC}: $public_ip"
    echo -e "${WHITE} Domain       ${NC}: $domain"
    echo -e "${WHITE} Interface    ${NC}: $interface"
    echo -e "${WHITE} Received     ${NC}: $rx_bytes"
    echo -e "${WHITE} Transmitted  ${NC}: $tx_bytes"
}

# Function to display subscription info
display_subscription_info() {
    echo -e "${RED}=========================================${NC}"
    echo -e "${BLUE}           SUBSCRIPTION INFORMATION            ${NC}"
    echo -e "${RED}=========================================${NC}"
    echo -e "${WHITE} Client Name  ${NC}: VIP-MEMBERS"
    echo -e "${WHITE} Exp Script   ${NC}: Lifetime"
    echo -e "${WHITE} Version      ${NC}: 2.0 Enhanced"
    echo -e "${WHITE} Last Update  ${NC}: $(date +'%Y-%m-%d %H:%M:%S')"
}

# Function to display service status
display_service_status() {
    echo -e "${RED}=========================================${NC}"
    echo -e "${BLUE}              SERVICE STATUS                 ${NC}"
    echo -e "${RED}=========================================${NC}"
    
    # Core Services
    echo -e "${WHITE} SSH / TUN              ${NC}: $(check_service_status ssh init.d)"
    echo -e "${WHITE} Dropbear               ${NC}: $(check_service_status dropbear init.d)"
    echo -e "${WHITE} Stunnel4               ${NC}: $(check_service_status stunnel4 init.d)"
    echo -e "${WHITE} Fail2Ban               ${NC}: $(check_service_status fail2ban init.d)"
    echo -e "${WHITE} Cron                   ${NC}: $(check_service_status cron init.d)"
    echo -e "${WHITE} Nginx                  ${NC}: $(check_service_status nginx init.d)"
    
    # Xray Services
    echo -e "${WHITE} XRAY Core              ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} XRAY Vmess TLS         ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} XRAY Vmess None TLS    ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} XRAY Vless TLS         ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} XRAY Vless None TLS    ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} XRAY Trojan            ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} XRAY Shadowsocks       ${NC}: $(check_service_status xray systemctl)"
    echo -e "${WHITE} SSLH                   ${NC}: $(check_service_status sslh systemctl)"
    
    # WebSocket Services
    echo -e "${WHITE} SSH WebSocket          ${NC}: $(check_service_status ws-proxy.service systemctl)"
    
    # Additional Services
    echo -e "${WHITE} VnStat                 ${NC}: $(check_service_status vnstat init.d)"
    echo -e "${WHITE} BadVPN                 ${NC}: $(udpgw-status)"
}

# Function to display footer
display_footer() {
    echo -e "${RED}=========================================${NC}"
    echo -e "${BLUE}               t.me/givps_com                 ${NC}"
    echo -e "${RED}=========================================${NC}"
}

# Main function
main() {
    display_header
    display_system_info
    display_subscription_info
    display_service_status
    display_footer
    
    echo ""
    read -n 1 -s -r -p "Press any key to return to main menu..."
    
    # Return to main menu
    menu
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    main
else
    echo -e "${RED}This script must be run as root!${NC}"
    exit 1
fi
