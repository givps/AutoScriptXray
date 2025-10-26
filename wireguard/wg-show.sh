#!/bin/bash
# =========================================
# SHOW WIREGUARD USERS - IMPROVED VERSION
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
readonly EXPIRY_DB="/etc/wireguard/user_expiry.db"

# ---------- Functions ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

format_time() {
    local timestamp=$1
    if [[ -z "$timestamp" || "$timestamp" == "0" ]]; then
        echo "Never"
    else
        local current_time=$(date +%s)
        local diff=$((current_time - timestamp))
        
        if [[ $diff -lt 60 ]]; then
            echo "Just now"
        elif [[ $diff -lt 3600 ]]; then
            echo "$((diff / 60))m ago"
        elif [[ $diff -lt 86400 ]]; then
            echo "$((diff / 3600))h ago"
        else
            echo "$((diff / 86400))d ago"
        fi
    fi
}

get_user_status() {
    local user=$1
    local pubkey=$2
    local expiry_date=$3
    
    local today=$(date +%Y-%m-%d)
    
    # Check if expired
    if [[ -n "$expiry_date" && "$expiry_date" < "$today" ]]; then
        echo "EXPIRED"
        return
    fi
    
    # Check if active in WireGuard
    if wg show wg0 peers | grep -q "$pubkey"; then
        local handshake=$(wg show wg0 latest-handshakes | grep "$pubkey" | awk '{print $2}')
        if [[ -n "$handshake" && "$handshake" != "0" ]]; then
            local current_time=$(date +%s)
            local time_diff=$((current_time - handshake))
            # If handshake was within last 3 minutes, consider active
            if [[ $time_diff -lt 180 ]]; then
                echo "ACTIVE"
                return
            else
                echo "INACTIVE"
                return
            fi
        fi
    fi
    
    echo "OFFLINE"
}

get_user_info() {
    local user=$1
    
    # Try to get from expiry database first
    local expiry_date=""
    local public_key=""
    local client_ip=""
    
    if [[ -f "$EXPIRY_DB" ]]; then
        IFS='|' read -r username expiry_date public_key <<< "$(grep "^$user|" "$EXPIRY_DB")"
    fi
    
    # If not in expiry DB, try to get from WireGuard config
    if [[ -z "$public_key" ]]; then
        local line_start=$(grep -n "^# $user\$" "$WG_CONF" | cut -d: -f1)
        if [[ -n "$line_start" ]]; then
            public_key=$(sed -n "$((line_start+1)),$((line_start+5))p" "$WG_CONF" | grep PublicKey | awk '{print $3}')
            client_ip=$(sed -n "$((line_start+1)),$((line_start+5))p" "$WG_CONF" | grep AllowedIPs | awk '{print $3}')
        fi
    fi
    
    # If still no public key, try client config
    if [[ -z "$public_key" && -f "$CLIENT_DIR/$user.conf" ]]; then
        public_key=$(grep -m1 "^PrivateKey" "$CLIENT_DIR/$user.conf" | awk '{print $3}' | wg pubkey 2>/dev/null || echo "")
        client_ip=$(grep -m1 "^Address" "$CLIENT_DIR/$user.conf" | awk '{print $3}')
    fi
    
    echo "$public_key|$client_ip|$expiry_date"
}

display_user_table() {
    local users=()
    
    # Collect users from multiple sources
    if [[ -f "$EXPIRY_DB" ]]; then
        while IFS='|' read -r user expiry_date public_key; do
            if [[ -n "$user" ]]; then
                users+=("$user")
            fi
        done < "$EXPIRY_DB"
    fi
    
    # Also get users from WireGuard config
    if [[ -f "$WG_CONF" ]]; then
        grep "^# " "$WG_CONF" | grep -v "^# \[Interface\]" | while read -r comment; do
            user=$(echo "$comment" | awk '{print $2}')
            if [[ -n "$user" && ! " ${users[@]} " =~ " $user " ]]; then
                users+=("$user")
            fi
        done
    fi
    
    # Also check client config files
    shopt -s nullglob
    for conf in "$CLIENT_DIR"/*.conf; do
        user=$(basename "$conf" .conf)
        if [[ -n "$user" && ! " ${users[@]} " =~ " $user " ]]; then
            users+=("$user")
        fi
    done
    shopt -u nullglob
    
    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${yellow}⚠️  No WireGuard users found.${nc}"
        return 1
    fi
    
    # Sort users alphabetically
    IFS=$'\n' users=($(sort <<<"${users[*]}"))
    unset IFS
    
    # Display header
    echo
    printf "%-20s %-15s %-12s %-12s %-15s %s\n" \
        "USER" "IP ADDRESS" "STATUS" "EXPIRY" "HANDSHAKE" "TRANSFER"
    echo -e "${red}----------------------------------------------------------------------------------------${nc}"
    
    local total_users=0
    local active_users=0
    
    for user in "${users[@]}"; do
        local user_info
        user_info=$(get_user_info "$user")
        IFS='|' read -r public_key client_ip expiry_date <<< "$user_info"
        
        # Get WireGuard statistics
        local handshake=""
        local transfer_rx=""
        local transfer_tx=""
        local status="UNKNOWN"
        
        if [[ -n "$public_key" ]]; then
            # Get handshake time
            handshake=$(wg show wg0 latest-handshakes 2>/dev/null | grep "$public_key" | awk '{print $2}')
            
            # Get transfer data
            transfer_rx=$(wg show wg0 transfer 2>/dev/null | grep "$public_key" | awk '{print $2}')
            transfer_tx=$(wg show wg0 transfer 2>/dev/null | grep "$public_key" | awk '{print $3}')
            
            # Get status
            status=$(get_user_status "$user" "$public_key" "$expiry_date")
        fi
        
        # Format output
        local handshake_str=$(format_time "$handshake")
        local transfer_str=""
        if [[ -n "$transfer_rx" || -n "$transfer_tx" ]]; then
            transfer_str="↓$(format_bytes "$transfer_rx")/↑$(format_bytes "$transfer_tx")"
        else
            transfer_str="No data"
        fi
        
        # Color code status
        local status_color=""
        case "$status" in
            "ACTIVE") status_color="$green" ;;
            "INACTIVE") status_color="$yellow" ;;
            "EXPIRED") status_color="$red" ;;
            "OFFLINE") status_color="$white" ;;
            *) status_color="$white" ;;
        esac
        
        # Color code expiry
        local expiry_color=""
        local today=$(date +%Y-%m-%d)
        if [[ -n "$expiry_date" ]]; then
            if [[ "$expiry_date" < "$today" ]]; then
                expiry_color="$red"
            else
                local days_until=$(( ($(date -d "$expiry_date" +%s) - $(date -d "$today" +%s)) / 86400 ))
                if [[ $days_until -le 7 ]]; then
                    expiry_color="$yellow"
                else
                    expiry_color="$green"
                fi
            fi
        else
            expiry_color="$white"
        fi
        
        printf "%-20s %-15s ${status_color}%-12s${nc} ${expiry_color}%-12s${nc} %-15s %s\n" \
            "$user" \
            "${client_ip:-N/A}" \
            "$status" \
            "${expiry_date:-Never}" \
            "$handshake_str" \
            "$transfer_str"
        
        ((total_users++))
        if [[ "$status" == "ACTIVE" ]]; then
            ((active_users++))
        fi
    done
    
    echo -e "${red}----------------------------------------------------------------------------------------${nc}"
    echo -e "${blue}📊 Summary: ${green}$active_users active${nc} / ${white}$total_users total${nc} users"
}

show_detailed_stats() {
    echo
    echo -e "${yellow}📈 WireGuard Interface Statistics:${nc}"
    echo -e "${red}-----------------------------------------${nc}"
    
    # Show interface statistics
    if ip link show wg0 >/dev/null 2>&1; then
        echo -e "${blue}Interface:${nc} $(ip -br addr show wg0 | awk '{print $1 " - " $3}')"
        echo -e "${blue}Peers:${nc} $(wg show wg0 peers | wc -l) connected"
        echo
    fi
    
    # Show recent handshakes
    echo -e "${yellow}Recent Activity:${nc}"
    wg show wg0 latest-handshakes | while read -r peer handshake; do
        if [[ "$handshake" != "0" ]]; then
            local user=""
            # Try to find user by public key
            if [[ -f "$EXPIRY_DB" ]]; then
                user=$(grep "$peer" "$EXPIRY_DB" | cut -d'|' -f1)
            fi
            if [[ -z "$user" ]]; then
                user=$(grep -B5 "$peer" "$WG_CONF" | grep "^# " | tail -1 | awk '{print $2}')
            fi
            echo -e "  ${white}${user:-Unknown}${nc}: $(format_time "$handshake")"
        fi
    done
}

# ---------- Main Execution ----------
main() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         🔍 WireGuard Users            ${nc}"
    echo -e "${red}=========================================${nc}"
    
    # Check if WireGuard is installed
    if ! command -v wg >/dev/null 2>&1; then
        log_error "WireGuard is not installed!"
        read -n 1 -s -r -p "Press any key to return to menu..."
        clear
        m-wg
        return
    fi
    
    # Check if WireGuard service is active
    if ! systemctl is-active --quiet wg-quick@wg0; then
        log_warn "WireGuard service is not active!"
        echo -e "Run: ${green}systemctl start wg-quick@wg0${nc}"
        echo
        read -n 1 -s -r -p "Press any key to return to menu..."
        clear
        m-wg
        return
    fi
    
    # Check if WireGuard interface exists
    if ! ip link show wg0 >/dev/null 2>&1; then
        log_error "WireGuard interface wg0 not found!"
        read -n 1 -s -r -p "Press any key to return to menu..."
        clear
        m-wg
        return
    fi
    
    # Display user table
    if ! display_user_table; then
        echo
        read -n 1 -s -r -p "Press any key to return to menu..."
        clear
        m-wg
        return
    fi
    
    # Show detailed statistics
    show_detailed_stats
    
    echo
    echo -e "${green}=========================================${nc}"
    echo -e "${blue}           📋 Quick Commands            ${nc}"
    echo -e "${green}=========================================${nc}"
    echo -e "Add user:    ${white}wg-add${nc}"
    echo -e "Delete user: ${white}wg-del${nc}"
    echo -e "Renew user:  ${white}wg-renew${nc}"
    echo -e "Full status: ${white}wg show wg0${nc}"
    echo -e "${green}=========================================${nc}"
    
    read -n 1 -s -r -p "Press any key to return to menu..."
    clear
    m-wg
}

# Run main function
main
