#!/bin/bash
# =========================================
# SERVICE RESTART MENU
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Configuration ----------
LOG_FILE="/var/log/service-restart.log"
STATS_FILE="/tmp/service_restart_stats.txt"

# ---------- Service Definitions ----------
declare -A SERVICES=(
    ["sshd"]="systemctl restart sshd"
    ["sslh"]="systemctl restart sslh"
    ["openvpn"]="systemctl restart openvpn"
    ["dropbear"]="systemctl restart dropbear" 
    ["stunnel4"]="systemctl restart stunnel4"
    ["fail2ban"]="systemctl restart fail2ban"
    ["cron"]="systemctl restart cron"
    ["nginx"]="systemctl restart nginx"
    ["xray"]="systemctl restart xray"
    ["netfilter-persistent"]="systemctl restart netfilter-persistent"
    ["ws-proxy"]="systemctl restart ws-proxy"
)

# ---------- Functions ----------

# Logging function
log_message() {
    local message=$1
    local level=${2:-"INFO"}
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $level - $message" | tee -a "$LOG_FILE"
}

# Track restart statistics
track_restart() {
    local service=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $service" >> "$STATS_FILE"
}

# Validate service name
validate_service_name() {
    local service=$1
    if [[ ! "$service" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        log_message "Invalid service name: $service" "ERROR"
        return 1
    fi
    return 0
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    local required_commands=("systemctl" "screen" "pkill")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "[ ${red}ERROR${nc} ] Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    return 0
}

# Cleanup function
cleanup() {
    echo -e "\n[ ${yellow}INFO${nc} ] Script interrupted. Cleaning up..."
    exit 0
}

# Function to display header
display_header() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           SERVICE RESTART MENU           ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e ""
}

# Function to display menu options
display_menu() {
    echo -e " ${cyan}1${nc}   Restart All Services"
    echo -e " ${cyan}2${nc}   Restart OpenSSH"
    echo -e " ${cyan}3${nc}   Restart Dropbear"
    echo -e " ${cyan}4${nc}   Restart Stunnel4"
    echo -e " ${cyan}5${nc}   Restart Nginx"
    echo -e " ${cyan}6${nc}   Restart Badvpn"
    echo -e " ${cyan}7${nc}   Restart Xray"
    echo -e " ${cyan}8${nc}   Restart Websocket"
    echo -e " ${cyan}9${nc}   Restart SSLH"
    echo -e " ${cyan}10${nc}  Restart IPtables"
    echo -e " ${cyan}11${nc}  Restart OpenVPN"
    echo -e " ${cyan}12${nc}  Show Service Status"
    echo -e ""
    echo -e " [${red}0${nc}] ${red}Back To Main Menu${nc}"
    echo -e ""
    echo -e " Press ${red}x${nc} or [ ${red}Ctrl+C${nc} ] To Exit"
    echo -e ""
    echo -e "${red}=========================================${nc}"
    echo -e ""
}

# Function to check if service exists and restart it
restart_service() {
    local service_name=$1
    local service_cmd=$2
    local display_name=$3
    
    echo -e "[ ${yellow}INFO${nc} ] Restarting $display_name..."
    log_message "Attempting to restart service: $display_name"
    
    # Validate service name
    if ! validate_service_name "$service_name"; then
        return 1
    fi
    
    # Check if service exists in systemd
    if ! systemctl list-unit-files | grep -q "$service_name"; then
        echo -e "[ ${red}ERROR${nc} ] Service $display_name not found in systemd"
        log_message "Service $display_name not found" "ERROR"
        return 1
    fi
    
    # Attempt to restart service with timeout
    if timeout 30s bash -c "$service_cmd" 2>/dev/null; then
        # Wait a moment and verify service status
        sleep 2
        if systemctl is-active --quiet "$service_name"; then
            echo -e "[ ${green}OK${nc} ] $display_name restarted successfully"
            log_message "Successfully restarted service: $display_name"
            track_restart "$display_name"
            return 0
        else
            echo -e "[ ${red}ERROR${nc} ] $display_name failed to start after restart"
            log_message "Service $display_name failed to start after restart" "ERROR"
            return 1
        fi
    else
        echo -e "[ ${red}ERROR${nc} ] Failed to restart $display_name (timeout or error)"
        log_message "Failed to restart service: $display_name" "ERROR"
        # Show detailed error information
        echo -e "[ ${yellow}DEBUG${nc} ] Service status:"
        systemctl status "$service_name" --no-pager -l --lines=5
        return 1
    fi
}

# Function to check service status
check_service_status() {
    local service_name=$1
    local display_name=$2
    
    if systemctl is-active --quiet "$service_name"; then
        echo -e "[ ${green}ACTIVE${nc} ] $display_name"
    else
        echo -e "[ ${red}INACTIVE${nc} ] $display_name"
    fi
}

# Enhanced BadVPN restart function
restart_badvpn() {
    local ports=("7100" "7200" "7300" "7400" "7500" "7600" "7700" "7800" "7900")
    
    echo -e "[ ${yellow}INFO${nc} ] Restarting BadVPN..."
    log_message "Starting BadVPN restart process"
    
    # Kill existing processes more safely
    if pgrep -f "badvpn-udpgw" > /dev/null; then
        pkill -f "badvpn-udpgw"
        echo -e "[ ${yellow}INFO${nc} ] Killed existing BadVPN processes"
        sleep 2
    fi
    
    # Kill any remaining processes forcefully
    if pgrep -f "badvpn-udpgw" > /dev/null; then
        pkill -9 -f "badvpn-udpgw"
        echo -e "[ ${yellow}WARN${nc} ] Forcefully killed remaining BadVPN processes"
        sleep 1
    fi
    
    # Start new instances
    local success_count=0
    for port in "${ports[@]}"; do
        if screen -dmS "badvpn-$port" badvpn-udpgw --listen-addr "127.0.0.1:$port" --max-clients 1000 2>/dev/null; then
            echo -e "[ ${green}OK${nc} ] BadVPN started on port $port"
            ((success_count++))
        else
            echo -e "[ ${red}ERROR${nc} ] Failed to start BadVPN on port $port"
            log_message "Failed to start BadVPN on port $port" "ERROR"
        fi
        sleep 0.1
    done
    
    if [ $success_count -eq ${#ports[@]} ]; then
        echo -e "[ ${green}SUCCESS${nc} ] All BadVPN instances started successfully"
        log_message "All BadVPN instances restarted successfully"
    else
        echo -e "[ ${yellow}WARN${nc} ] $success_count/${#ports[@]} BadVPN instances started"
        log_message "Partial BadVPN restart: $success_count/${#ports[@]} instances" "WARN"
    fi
}

# Function to show service status
show_service_status() {
    echo -e ""
    echo -e "[ ${yellow}SERVICE STATUS${nc} ]"
    echo -e "${red}-----------------------------------------${nc}"
    check_service_status "sshd" "OpenSSH"
    check_service_status "sslh" "SSLH"
    check_service_status "openvpn" "OpenVPN"
    check_service_status "dropbear" "Dropbear" 
    check_service_status "stunnel4" "Stunnel4"
    check_service_status "nginx" "Nginx"
    check_service_status "xray" "Xray"
    check_service_status "fail2ban" "Fail2Ban"
    check_service_status "cron" "Cron"
    check_service_status "netfilter-persistent" "IPtables"
    
    # Check BadVPN status
    local badvpn_count=$(pgrep -f "badvpn-udpgw" | wc -l)
    if [ "$badvpn_count" -ge 1 ]; then
        echo -e "[ ${green}ACTIVE${nc} ] BadVPN ($badvpn_count instances)"
    else
        echo -e "[ ${red}INACTIVE${nc} ] BadVPN"
    fi
    
    # Check WebSocket services
    check_service_status "ws-proxy" "WebSocket Service"
    echo -e "${red}-----------------------------------------${nc}"
    echo -e ""
}

# Function to restart all services
restart_all_services() {
    display_header
    echo -e "[ ${yellow}INFO${nc} ] Restarting All Services..."
    log_message "Starting complete service restart process"
    echo -e "${red}=========================================${nc}"
    echo -e ""
    
    local failed_services=()
    
    # Restart systemd services
    for service in "${!SERVICES[@]}"; do
        if ! restart_service "$service" "${SERVICES[$service]}" "${service^}"; then
            failed_services+=("$service")
        fi
        sleep 0.5
    done
    
    echo -e ""
    echo -e "[ ${yellow}INFO${nc} ] Restarting Additional Services..."
    echo -e "${red}-----------------------------------------${nc}"
    
    # Restart BadVPN
    restart_badvpn
    
    # Show summary
    echo -e ""
    if [ ${#failed_services[@]} -eq 0 ]; then
        echo -e "[ ${green}SUCCESS${nc} ] All services have been restarted successfully!"
        log_message "All services restarted successfully" "SUCCESS"
    else
        echo -e "[ ${yellow}WARN${nc} ] Some services failed to restart: ${failed_services[*]}"
        log_message "Some services failed to restart: ${failed_services[*]}" "WARN"
    fi
    
    echo -e ""
    echo -e "${red}=========================================${nc}"
}

# Wait for user input
wait_for_input() {
    echo -e ""
    read -n 1 -s -r -p "Press any key to continue..."
}

# Main restart function
restart() {
    # Set trap for cleanup
    trap cleanup SIGINT SIGTERM
    
    while true; do
        display_header
        display_menu
        
        read -p " Select menu [0-12]: " Restart
        
        case $Restart in
            1)
                restart_all_services
                show_service_status
                wait_for_input
                ;;
            2)
                display_header
                restart_service "sshd" "systemctl restart sshd" "OpenSSH"
                show_service_status
                wait_for_input
                ;;
            3)
                display_header
                restart_service "dropbear" "systemctl restart dropbear" "Dropbear"
                show_service_status
                wait_for_input
                ;;
            4)
                display_header
                restart_service "stunnel4" "systemctl restart stunnel4" "Stunnel4"
                show_service_status
                wait_for_input
                ;;
            5)
                display_header
                restart_service "nginx" "systemctl restart nginx" "Nginx"
                show_service_status
                wait_for_input
                ;;
            6)
                display_header
                restart_badvpn
                show_service_status
                wait_for_input
                ;;
            7)
                display_header
                restart_service "xray" "systemctl restart xray.service" "Xray Service"
                show_service_status
                wait_for_input
                ;;
            8)
                display_header
                restart_service "ws-proxy" "systemctl restart ws-proxy" "WebSocket Service"
                show_service_status
                wait_for_input
                ;;
            9)
                display_header
                restart_service "sslh" "systemctl restart sslh" "SSLH"
                show_service_status
                wait_for_input
                ;;
            10)
                display_header
                restart_service "netfilter-persistent" "systemctl restart netfilter-persistent" "IPtables"
                show_service_status
                wait_for_input
                ;;
            11)
                display_header
                restart_service "openvpn" "systemctl restart openvpn" "OpenVPN"
                show_service_status
                wait_for_input
                ;;
            12)
                display_header
                show_service_status
                wait_for_input
                ;;
            0)
                echo -e "[ ${green}INFO${nc} ] Returning to main menu..."
                log_message "Returning to main menu" "INFO"
                sleep 1
                # Uncomment if you have main menu function
                # m-system
                exit 0
                ;;
            x|X)
                echo -e "[ ${green}INFO${nc} ] Goodbye!"
                log_message "Script terminated by user" "INFO"
                exit 0
                ;;
            *)
                echo -e "[ ${red}ERROR${nc} ] Invalid option! Please select 0-12 or x"
                sleep 2
                ;;
        esac
    done
}

# ---------- Main Execution ----------
main() {
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Verify root privileges
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}This script must be run as root!${nc}"
        echo -e "Please run with: ${cyan}sudo $0${nc}"
        exit 1
    fi
    
    # Initialize log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log_message "Service Restart Menu started" "INFO"
    
    # Start the restart menu
    restart
}

# Run main function
main "$@"
