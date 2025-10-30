#!/bin/bash
# =========================================
# WIREGUARD MENU
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Configuration ----------
WG_CONF="/etc/wireguard/wg0.conf"
CLIENT_DIR="/etc/wireguard/clients"

# ---------- Log Helpers ----------
log_error()   { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn()    { echo -e "${yellow}⚠️ $1${nc}"; }
log_info()    { echo -e "${blue}ℹ️ $1${nc}"; }

# ---------- WireGuard Status ----------
check_wireguard_status() {
    if ! command -v wg &>/dev/null; then
        echo "NOT_INSTALLED"
        return
    fi

    if systemctl is-active --quiet wg-quick@wg0; then
        service_status="${green}ACTIVE${nc}"
    else
        service_status="${red}INACTIVE${nc}"
    fi

    if ip link show wg0 &>/dev/null; then
        [[ $(cat /sys/class/net/wg0/operstate 2>/dev/null) == "up" ]] && \
            interface_status="${green}UP${nc}" || interface_status="${yellow}DOWN${nc}"
    else
        interface_status="${red}MISSING${nc}"
    fi

    echo "$service_status|$interface_status"
}

# ---------- Server Info ----------
get_server_info() {
    local ip port pubkey
    ip=$(curl -s -4 ipv4.icanhazip.com || curl -s -4 ifconfig.me || echo "Unknown")
    port=$(grep -m1 "^ListenPort" "$WG_CONF" 2>/dev/null | awk '{print $3}')
    privkey=$(grep -m1 "^PrivateKey" "$WG_CONF" 2>/dev/null | awk '{print $3}')
    pubkey=$( [[ -n "$privkey" ]] && echo "$privkey" | wg pubkey 2>/dev/null || echo "Unknown" )
    echo "$ip|${port:-Unknown}|$pubkey"
}

# ---------- User Stats ----------
get_user_stats() {
    local total=0 active=0
    [[ -d "$CLIENT_DIR" ]] && total=$(ls -1 "$CLIENT_DIR"/*.conf 2>/dev/null | wc -l)
    [[ $(systemctl is-active wg-quick@wg0) == "active" ]] && active=$(wg show wg0 peers 2>/dev/null | wc -l)
    echo "$total|$active"
}

# ---------- Display Server Status ----------
show_server_status() {
    IFS='|' read -r svc iface <<< "$(check_wireguard_status)"
    IFS='|' read -r ip port pub <<< "$(get_server_info)"
    IFS='|' read -r total active <<< "$(get_user_stats)"

    echo -e "${blue}🛡️  WireGuard Server Status${nc}"
    echo -e "${red}-----------------------------------------${nc}"
    echo -e " Service:    $svc"
    echo -e " Interface:  $iface"
    echo -e " Users:      ${white}${active}${nc} active / ${white}${total}${nc} total"
    echo -e " Server IP:  ${yellow}${ip}${nc}"
    echo -e " Port:       ${yellow}${port}${nc}"
    [[ "$pub" != "Unknown" ]] && echo -e " Public Key: ${green}${pub:0:20}...${nc}"

    if [[ "$svc" == *ACTIVE* ]]; then
        local hs=$(wg show wg0 latest-handshakes 2>/dev/null | awk '$2>0' | wc -l)
        echo -e " Active Peers: ${white}${hs}${nc}"
    fi
    echo -e "${red}-----------------------------------------${nc}"
}

# ---------- Dependency Check ----------
check_scripts() {
    local missing=()
    for cmd in wg-add wg-del wg-show wg-renew; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing scripts: ${missing[*]}"
        echo "Run WireGuard setup to restore them."
        return 1
    fi
    return 0
}

# ---------- Quick Actions ----------
quick_add_user() {
    read -rp "Enter username: " user
    [[ -z "$user" ]] && { log_error "Username cannot be empty"; return; }
    local expiry=$(date -d "+30 days" +%Y-%m-%d)
    log_info "Creating '$user' (expires: $expiry)"
    if wg-add "$user" "$expiry"; then
        log_success "User '$user' created successfully!"
    else
        log_error "Failed to create user."
    fi
}

reload_configuration() {
    log_info "Reloading WireGuard configuration..."
    if wg syncconf wg0 <(wg-quick strip wg0 2>/dev/null); then
        log_success "Reloaded live configuration."
    else
        log_warn "Live reload failed, restarting..."
        if systemctl restart wg-quick@wg0; then
            log_success "Service restarted successfully!"
        else
            log_error "Failed to restart service!"
        fi
    fi
}

view_service_logs() {
    echo
    log_info "Last 10 log entries:"
    echo -e "${red}-----------------------------------------${nc}"
    journalctl -u wg-quick@wg0 -n 10 --no-pager
    echo -e "${red}-----------------------------------------${nc}"
    read -n 1 -s -r -p "Press any key..."
}

config_check() {
    echo -e "${yellow}🔧 Configuration Check:${nc}"
    echo -e "${red}-----------------------------------------${nc}"
    local ok=0 total=4
    [[ -f "$WG_CONF" ]] && { echo -e " ✅ Config file: $WG_CONF"; ((ok++)); } || echo " ❌ Missing config"
    [[ -d "$CLIENT_DIR" ]] && { echo -e " ✅ Client dir: $CLIENT_DIR"; ((ok++)); } || echo " ❌ Missing clients folder"
    [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] && { echo " ✅ IP forwarding enabled"; ((ok++)); } || echo " ❌ IP forwarding disabled"
    systemctl is-enabled wg-quick@wg0 &>/dev/null && { echo " ✅ Service enabled at boot"; ((ok++)); } || echo " ❌ Service not enabled"
    echo -e "${red}-----------------------------------------${nc}"
    [[ $ok -eq $total ]] && log_success "All checks passed!" || log_warn "$ok/$total checks passed."
}

# ---------- Main Menu ----------
main_menu() {
    while true; do
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}       ⚙️  WIREGUARD VPN MENU           ${nc}"
        echo -e "${red}=========================================${nc}"

        show_server_status
        echo
        check_scripts

        echo -e "${blue}📋 Management Options:${nc}"
        echo -e " 1) Add WireGuard User"
        echo -e " 2) Delete WireGuard User"
        echo -e " 3) Show Users"
        echo -e " 4) Renew User"
        echo -e " 5) Restart Service"
        echo -e " 6) Check Configuration"
        echo -e "-----------------------------------------"
        echo -e " a) Quick Add User (30 days)"
        echo -e " r) Reload Configuration"
        echo -e " l) View Logs"
        echo -e " c) Show Partial Config"
        echo -e " 0) Back / Exit"
        echo -e "-----------------------------------------"
        read -rp "Select option: " opt

        case "$opt" in
            1) command -v wg-add &>/dev/null && wg-add || log_error "wg-add not found" ;;
            2) command -v wg-del &>/dev/null && wg-del || log_error "wg-del not found" ;;
            3) command -v wg-show &>/dev/null && wg-show || log_error "wg-show not found" ;;
            4) command -v wg-renew &>/dev/null && wg-renew || log_error "wg-renew not found" ;;
            5) systemctl restart wg-quick@wg0 && log_success "Service restarted" || log_error "Restart failed"; sleep 2 ;;
            6) config_check; read -n 1 -s -r -p "Press any key..." ;;
            a|A) quick_add_user; read -n 1 -s -r -p "Press any key..." ;;
            r|R) reload_configuration; sleep 2 ;;
            l|L) view_service_logs ;;
            c|C) echo; grep -E "^(Address|ListenPort|#)" "$WG_CONF" | head -10; read -n 1 -s -r -p "Press any key..." ;;
            0|x|X|q|Q) echo -e "${green}Goodbye! 👋${nc}"; exit 0 ;;
            *) log_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# ---------- Initial Check ----------
if ! command -v wg &>/dev/null; then
    log_error "WireGuard is not installed!"
    exit 1
fi

main_menu
