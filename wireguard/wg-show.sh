#!/bin/bash
# =========================================
# SHOW WIREGUARD USER
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

# ---------- Utility Functions ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

format_bytes() {
    local bytes=$1
    if [[ -z "$bytes" || "$bytes" == "0" ]]; then
        echo "0 B"
    elif (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(bc -l <<< "$bytes/1073741824")"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(bc -l <<< "$bytes/1048576")"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(bc -l <<< "$bytes/1024")"
    else
        echo "${bytes} B"
    fi
}

format_time() {
    local timestamp=$1
    if [[ -z "$timestamp" || "$timestamp" == "0" ]]; then
        echo "Never"
        return
    fi
    local now diff
    now=$(date +%s)
    diff=$((now - timestamp))
    if (( diff < 60 )); then
        echo "${diff}s ago"
    elif (( diff < 3600 )); then
        echo "$((diff / 60))m ago"
    elif (( diff < 86400 )); then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# ---------- Get user data ----------
get_user_info() {
    local user=$1
    local expiry_date="" public_key="" client_ip=""

    if [[ -f "$EXPIRY_DB" ]]; then
        IFS='|' read -r _expiry_user expiry_date public_key <<< "$(grep -m1 "^$user|" "$EXPIRY_DB")"
    fi

    if [[ -z "$public_key" && -f "$WG_CONF" ]]; then
        local line_start
        line_start=$(grep -n "^# $user\$" "$WG_CONF" | cut -d: -f1)
        if [[ -n "$line_start" ]]; then
            public_key=$(sed -n "$((line_start+1)),$((line_start+6))p" "$WG_CONF" | grep -m1 "PublicKey" | awk '{print $3}')
            client_ip=$(sed -n "$((line_start+1)),$((line_start+6))p" "$WG_CONF" | grep -m1 "AllowedIPs" | awk '{print $3}')
        fi
    fi

    echo "$public_key|$client_ip|$expiry_date"
}

# ---------- Determine user status ----------
get_user_status() {
    local pubkey=$1
    local expiry_date=$2
    local today
    today=$(date +%Y-%m-%d)

    # Expiry check
    if [[ -n "$expiry_date" && "$expiry_date" < "$today" ]]; then
        echo "EXPIRED"
        return
    fi

    # Active check
    local handshake
    handshake=$(wg show wg0 latest-handshakes 2>/dev/null | grep "$pubkey" | awk '{print $2}')
    if [[ -n "$handshake" && "$handshake" != "0" ]]; then
        local diff=$(( $(date +%s) - handshake ))
        if (( diff < 180 )); then
            echo "ACTIVE"
        else
            echo "INACTIVE"
        fi
    else
        echo "OFFLINE"
    fi
}

# ---------- Display table ----------
display_user_table() {
    local users=()

    # From expiry DB
    [[ -f "$EXPIRY_DB" ]] && while IFS='|' read -r user _ _; do
        [[ -n "$user" ]] && users+=("$user")
    done < "$EXPIRY_DB"

    # From wg0.conf
    [[ -f "$WG_CONF" ]] && while read -r line; do
        user=$(awk '{print $2}' <<< "$line")
        [[ -n "$user" && ! " ${users[*]} " =~ " $user " ]] && users+=("$user")
    done < <(grep "^# " "$WG_CONF" | grep -v "\[Interface\]")

    # From clients directory
    for conf in "$CLIENT_DIR"/*.conf; do
        [[ -e "$conf" ]] || continue
        user=$(basename "$conf" .conf)
        [[ ! " ${users[*]} " =~ " $user " ]] && users+=("$user")
    done

    if (( ${#users[@]} == 0 )); then
        log_warn "No WireGuard users found."
        return 1
    fi

    IFS=$'\n' users=($(sort <<<"${users[*]}"))
    unset IFS

    echo
    printf "%-20s %-15s %-10s %-12s %-15s %s\n" \
        "USER" "IP" "STATUS" "EXPIRY" "HANDSHAKE" "TRANSFER"
    echo -e "${red}---------------------------------------------------------------------------------------${nc}"

    local total=0 active=0
    for user in "${users[@]}"; do
        IFS='|' read -r pubkey ip expiry <<< "$(get_user_info "$user")"
        local handshake rx tx
        handshake=$(wg show wg0 latest-handshakes | grep "$pubkey" | awk '{print $2}')
        rx=$(wg show wg0 transfer | grep "$pubkey" | awk '{print $2}')
        tx=$(wg show wg0 transfer | grep "$pubkey" | awk '{print $3}')
        local status
        status=$(get_user_status "$pubkey" "$expiry")
        [[ "$status" == "ACTIVE" ]] && ((active++))
        ((total++))

        local handshake_str=$(format_time "$handshake")
        local transfer_str="↓$(format_bytes "${rx:-0}")/↑$(format_bytes "${tx:-0}")"

        # Status color
        case "$status" in
            ACTIVE) status_color=$green ;;
            INACTIVE) status_color=$yellow ;;
            EXPIRED) status_color=$red ;;
            OFFLINE) status_color=$white ;;
            *) status_color=$white ;;
        esac

        # Expiry color
        local expiry_color=$white
        if [[ -n "$expiry" ]]; then
            if [[ "$expiry" < "$today" ]]; then
                expiry_color=$red
            elif (( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 <= 7 )); then
                expiry_color=$yellow
            else
                expiry_color=$green
            fi
        fi

        printf "%-20s %-15s ${status_color}%-10s${nc} ${expiry_color}%-12s${nc} %-15s %s\n" \
            "$user" "${ip:-N/A}" "$status" "${expiry:-Never}" "$handshake_str" "$transfer_str"
    done

    echo -e "${red}---------------------------------------------------------------------------------------${nc}"
    echo -e "${blue}📊 $active active${nc} / ${white}$total total${nc}"
}

# ---------- Extra Stats ----------
show_detailed_stats() {
    echo
    echo -e "${yellow}📈 Interface Statistics:${nc}"
    echo -e "${red}----------------------------------------${nc}"
    ip link show wg0 >/dev/null 2>&1 && {
        echo -e "${blue}Interface:${nc} $(ip -br addr show wg0 | awk '{print $1 " - " $3}')"
        echo -e "${blue}Peers:${nc} $(wg show wg0 peers | wc -l)"
        echo
    }
    echo -e "${yellow}Recent Activity:${nc}"
    wg show wg0 latest-handshakes | while read -r peer handshake; do
        [[ "$handshake" == "0" ]] && continue
        user=$(grep -F "$peer" "$EXPIRY_DB" 2>/dev/null | cut -d'|' -f1)
        [[ -z "$user" ]] && user=$(grep -B5 "$peer" "$WG_CONF" | grep "^# " | tail -1 | awk '{print $2}')
        echo -e "  ${white}${user:-Unknown}${nc}: $(format_time "$handshake")"
    done
}

# ---------- Main ----------
main() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         🔍 WireGuard Users            ${nc}"
    echo -e "${red}=========================================${nc}"

    if ! command -v wg &>/dev/null; then
        log_error "WireGuard not installed!"
        return
    fi

    if ! systemctl is-active --quiet wg-quick@wg0; then
        log_warn "WireGuard service inactive!"
        echo -e "Run: ${green}systemctl start wg-quick@wg0${nc}"
        return
    fi

    if ! ip link show wg0 &>/dev/null; then
        log_error "Interface wg0 not found!"
        return
    fi

    display_user_table && show_detailed_stats

    echo
    echo -e "${green}=========================================${nc}"
    echo -e "${blue}           📋 Quick Commands            ${nc}"
    echo -e "${green}=========================================${nc}"
    echo -e "Add user:    ${white}wg-add${nc}"
    echo -e "Delete user: ${white}wg-del${nc}"
    echo -e "Renew user:  ${white}wg-renew${nc}"
    echo -e "Full status: ${white}wg show wg0${nc}"
    echo -e "${green}=========================================${nc}"
}

main
