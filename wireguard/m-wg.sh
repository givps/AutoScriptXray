#!/bin/bash
# =========================================
# WIREGUARD MENU - IMPROVED VERSION
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Configuration ----------
readonly WG_CONF="/etc/wireguard/wg0.conf"
readonly CLIENT_DIR="/etc/wireguard/clients"

# ---------- Functions ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

check_wireguard_status() {
    local status_color interface_status service_status
    
    # Check if WireGuard is installed
    if ! command -v wg >/dev/null 2>&1; then
        echo -e "${red}⛔ NOT INSTALLED${nc}"
        return 1
    fi
    
    # Check service status
    if systemctl is-active --quiet wg-quick@wg0; then
        service_status="${green}ACTIVE${nc}"
    else
        service_status="${red}INACTIVE${nc}"
    fi
    
    # Check interface status
    if ip link show wg0 >/dev/null 2>&1; then
        if ip addr show wg0 | grep -q "state UP"; then
            interface_status="${green}UP${nc}"
        else
            interface_status="${yellow}DOWN${nc}"
        fi
    else
        interface_status="${red}MISSING${nc}"
    fi
    
    echo "$service_status|$interface_status"
}

get_server_info() {
    local server_ip server_port public_key
    
    # Get public IP
    server_ip=$(curl -s -4 ipv4.icanhazip.com 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null || echo "Unknown")
    
    # Get server port from config
    if [[ -f "$WG_CONF" ]]; then
        server_port=$(grep "^ListenPort" "$WG_CONF" | awk '{print $3}')
        public_key=$(grep "^PrivateKey" "$WG_CONF" | awk '{print $3}' | wg pubkey 2>/dev/null || echo "Unknown")
    else
        server_port="Unknown"
        public_key="Unknown"
    fi
    
    echo "$server_ip|$server_port|$public_key"
}

get_user_stats() {
    local total_users=0 active_users=0
    
    # Count from client config directory
    if [[ -d "$CLIENT_DIR" ]]; then
        shopt -s nullglob
        local client_files=("$CLIENT_DIR"/*.conf)
        shopt -u nullglob
        total_users=${#client_files[@]}
    fi
    
    # Count active peers (simplified)
    if command -v wg >/dev/null 2>&1 && systemctl is-active --quiet wg-quick@wg0; then
        active_users=$(wg show wg0 peers 2>/dev/null | wc -l)
    fi
    
    echo "$total_users|$active_users"
}

show_server_status() {
    local status_info server_info user_stats
    status_info=$(check_wireguard_status)
    server_info=$(get_server_info)
    user_stats=$(get_user_stats)
    
    IFS='|' read -r service_status interface_status <<< "$status_info"
    IFS='|' read -r server_ip server_port public_key <<< "$server_info"
    IFS='|' read -r total_users active_users <<< "$user_stats"
    
    echo -e "${blue}🛡️  WireGuard Server Status:${nc}"
    echo -e "${red}-----------------------------------------${nc}"
    echo -e " Service:    $service_status"
    echo -e " Interface:  $interface_status"
    echo -e " Users:      ${white}$active_users active${nc} / ${white}$total_users total${nc}"
    echo -e " Server IP:  ${yellow}$server_ip${nc}"
    echo -e " Port:       ${yellow}$server_port${nc}"
    
    if [[ "$public_key" != "Unknown" ]]; then
        echo -e " Public Key: ${green}${public_key:0:20}...${nc}"
    fi
    
    # Show recent activity
    if [[ "$service_status" == "${green}ACTIVE${nc}" ]]; then
        local recent_handshakes=$(wg show wg0 latest-handshakes 2>/dev/null | grep -v "0$" | wc -l)
        echo -e " Active:     ${white}$recent_handshakes recent handshakes${nc}"
    fi
    
    echo -e "${red}-----------------------------------------${nc}"
}

check_command_availability() {
    local missing_commands=()
    
    for cmd in wg-add wg-del wg-show wg-renew; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_warn "Missing management scripts: ${missing_commands[*]}"
        echo -e "Run the WireGuard setup script to install them."
        echo
        return 1
    fi
    return 0
}

show_quick_actions() {
    echo -e "${yellow}🚀 Quick Actions:${nc}"
    echo -e " ${white}a${nc}) Add user with default expiry"
    echo -e " ${white}s${nc}) Show detailed user statistics"
    echo -e " ${white}r${nc}) Reload configuration (no restart)"
    echo -e " ${white}l${nc}) View WireGuard service logs"
    echo -e " ${white}c${nc}) Check server configuration"
}

show_config_check() {
    echo -e "${yellow}🔧 Configuration Check:${nc}"
    echo -e "${red}-----------------------------------------${nc}"
    
    local checks=0
    local passed=0
    
    # Check 1: Config file exists
    ((checks++))
    if [[ -f "$WG_CONF" ]]; then
        echo -e " ${green}✅${nc} Config file: $WG_CONF"
        ((passed++))
    else
        echo -e " ${red}❌${nc} Config file missing: $WG_CONF"
    fi
    
    # Check 2: Client directory exists
    ((checks++))
    if [[ -d "$CLIENT_DIR" ]]; then
        echo -e " ${green}✅${nc} Client directory: $CLIENT_DIR"
        ((passed++))
    else
        echo -e " ${red}❌${nc} Client directory missing: $CLIENT_DIR"
    fi
    
    # Check 3: IP forwarding enabled
    ((checks++))
    if [[ $(sysctl -n net.ipv4.ip_forward) -eq 1 ]]; then
        echo -e " ${green}✅${nc} IP forwarding enabled"
        ((passed++))
    else
        echo -e " ${red}❌${nc} IP forwarding disabled"
    fi
    
    # Check 4: Service enabled
    ((checks++))
    if systemctl is-enabled wg-quick@wg0 >/dev/null 2>&1; then
        echo -e " ${green}✅${nc} Service enabled at boot"
        ((passed++))
    else
        echo -e " ${red}❌${nc} Service not enabled at boot"
    fi
    
    echo -e "${red}-----------------------------------------${nc}"
    echo -e "Result: $passed/$checks checks passed"
    
    if [[ $passed -eq $checks ]]; then
        log_success "All configuration checks passed!"
    else
        log_warn "Some configuration issues detected"
    fi
}

quick_add_user() {
    echo
    log_info "Quick User Creation"
    read -rp "Enter username: " user
    if [[ -z "$user" ]]; then
        log_error "Username cannot be empty"
        return 1
    fi
    
    # Auto-set expiry to 30 days from now
    local expiry_date=$(date -d "+30 days" +%Y-%m-%d)
    
    log_info "Creating user '$user' with auto-expiry: $expiry_date"
    if wg-add "$user" "$expiry_date"; then
        log_success "User created successfully!"
    else
        log_error "Failed to create user"
    fi
}

reload_configuration() {
    log_info "Reloading WireGuard configuration..."
    if wg syncconf wg0 <(wg-quick strip wg0 2>/dev/null); then
        log_success "Configuration reloaded successfully (no restart needed)"
    else
        log_warn "Live reload failed, restarting service..."
        if systemctl restart wg-quick@wg0; then
            log_success "Service restarted successfully"
        else
            log_error "Failed to restart service"
        fi
    fi
}

view_service_logs() {
    echo
    log_info "Showing recent WireGuard logs (last 10 lines):"
    echo -e "${red}-----------------------------------------${nc}"
    journalctl -u wg-quick@wg0 -n 10 --no-pager
    echo -e "${red}-----------------------------------------${nc}"
    read -n 1 -s -r -p "Press any key to continue..."
}

# ---------- Main Menu ----------
main_menu() {
    while true; do
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}       ⚙️  WIREGUARD VPN MENU           ${nc}"
        echo -e "${red}=========================================${nc}"
        
        # Show server status
        show_server_status
        echo
        
        # Check command availability
        if ! check_command_availability; then
            echo
        fi
        
        # Main menu options
        echo -e "${blue}📋 Management Options:${nc}"
        echo -e " ${white}1${nc}) Create WireGuard User"
        echo -e " ${white}2${nc}) Delete WireGuard User"
        echo -e " ${white}3${nc}) Show WireGuard Users"
        echo -e " ${white}4${nc}) Renew WireGuard User"
        echo -e " ${white}5${nc}) Restart WireGuard Service"
        echo -e " ${white}6${nc}) Check Server Configuration"
        
        echo -e "${red}-----------------------------------------${nc}"
        
        # Quick actions
        show_quick_actions
        
        echo -e "${red}=========================================${nc}"
        echo -e " ${white}0${nc}) Back to Main Menu"
        echo -e " Press ${yellow}x${nc} or ${yellow}q${nc} to Exit"
        echo -e "${red}=========================================${nc}"
        
        read -rp "Select menu option: " opt
        
        case "$opt" in
            1) 
                if command -v wg-add >/dev/null 2>&1; then
                    wg-add
                else
                    log_error "wg-add command not found"
                    sleep 2
                fi
                ;;
            2) 
                if command -v wg-del >/dev/null 2>&1; then
                    wg-del
                else
                    log_error "wg-del command not found"
                    sleep 2
                fi
                ;;
            3) 
                if command -v wg-show >/dev/null 2>&1; then
                    wg-show
                else
                    log_error "wg-show command not found"
                    sleep 2
                fi
                ;;
            4) 
                if command -v wg-renew >/dev/null 2>&1; then
                    wg-renew
                else
                    log_error "wg-renew command not found"
                    sleep 2
                fi
                ;;
            5)
                log_info "Restarting WireGuard service..."
                if systemctl restart wg-quick@wg0; then
                    log_success "WireGuard service restarted successfully!"
                else
                    log_error "Failed to restart WireGuard service."
                fi
                sleep 2
                ;;
            6)
                show_config_check
                read -n 1 -s -r -p "Press any key to continue..."
                ;;
            a|A)
                quick_add_user
                read -n 1 -s -r -p "Press any key to continue..."
                ;;
            s|S)
                if command -v wg-show >/dev/null 2>&1; then
                    clear
                    wg-show
                else
                    log_error "wg-show command not found"
                    sleep 2
                fi
                ;;
            r|R)
                reload_configuration
                sleep 2
                ;;
            l|L)
                view_service_logs
                ;;
            c|C)
                echo
                log_info "Server Configuration:"
                if [[ -f "$WG_CONF" ]]; then
                    echo -e "${red}-----------------------------------------${nc}"
                    grep -E "^(ListenPort|Address|PrivateKey|#)" "$WG_CONF" | head -10
                    echo -e "${red}-----------------------------------------${nc}"
                else
                    log_error "Configuration file not found"
                fi
                read -n 1 -s -r -p "Press any key to continue..."
                ;;
            0) 
                clear
                # Assuming there's a main menu function called 'menu'
                if command -v menu >/dev/null 2>&1; then
                    menu
                else
                    echo -e "${green}Returning to shell...${nc}"
                    exit 0
                fi
                break 
                ;;
            x|X|q|Q) 
                echo -e "${green}Goodbye! 👋${nc}"
                exit 0 
                ;;
            *) 
                log_error "Invalid option: $opt"
                sleep 1
                ;;
        esac
    done
}

# ---------- Initial Checks ----------
initial_check() {
    # Check if WireGuard is installed
    if ! command -v wg >/dev/null 2>&1; then
        log_error "WireGuard is not installed on this system!"
        echo -e "Please install WireGuard first."
        echo
        read -n 1 -s -r -p "Press any key to return to main menu..."
        clear
        # Return to whatever called this script
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$WG_CONF" ]]; then
        log_warn "WireGuard configuration not found: $WG_CONF"
        echo -e "You may need to set up WireGuard first."
        echo
    fi
    
    return 0
}

# ---------- Main Execution ----------
if initial_check; then
    main_menu
else
    # If WireGuard not installed, return to caller
    if command -v menu >/dev/null 2>&1; then
        menu
    else
        exit 1
    fi
fi
