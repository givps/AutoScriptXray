#!/bin/bash
set -euo pipefail
# =========================================
# RENEW WIREGUARD USER
# =========================================

# ---------- Colors ----------
red='\e[1;31m'; green='\e[0;32m'; yellow='\e[1;33m'; blue='\e[1;34m'; white='\e[1;37m'; nc='\e[0m'

# ---------- Configuration ----------
readonly WG_CONF="/etc/wireguard/wg0.conf"
readonly CLIENT_DIR="/etc/wireguard/clients"
readonly BACKUP_DIR="/etc/wireguard/backups"
readonly EXPIRY_DB="/etc/wireguard/user_expiry.db"
readonly LOG_DIR="/var/log/wireguard"
readonly RENEW_LOG="$LOG_DIR/user-renewals.log"

# ---------- Helpers ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

# ---------- Environment Validation ----------
validate_environment() {
    if [[ ! -f "$WG_CONF" ]]; then
        log_error "WireGuard configuration not found: $WG_CONF"
        return 1
    fi
    if ! command -v wg >/dev/null 2>&1; then
        log_error "WireGuard (wg) is not installed"
        return 1
    fi
    mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$CLIENT_DIR"
    chmod 700 "$BACKUP_DIR" "$LOG_DIR" "$CLIENT_DIR" || true
    touch "$RENEW_LOG"
    chmod 600 "$RENEW_LOG" || true
    return 0
}

# ---------- Existence Check (robust) ----------
check_user_exists() {
    local user=$1
    # expiry db (format: user|YYYY-MM-DD|public_key)
    if [[ -f "$EXPIRY_DB" ]] && grep -q -E "^${user}\|" "$EXPIRY_DB"; then
        return 0
    fi
    # In wg0.conf we accept comment formats:
    #  # user
    #  # user - added on ...
    #  # user (Exp: ...)
    if grep -q -E "^#\s+${user}(\s|$|[-(])" "$WG_CONF"; then
        return 0
    fi
    # client file
    [[ -f "${CLIENT_DIR}/${user}.conf" ]] && return 0
    return 1
}

# ---------- Get user info (public_key|client_ip|expiry) ----------
get_user_info() {
    local user=$1
    local public_key client_ip expiry_date line_start

    # From expiry DB
    if [[ -f "$EXPIRY_DB" ]] && grep -q -E "^${user}\|" "$EXPIRY_DB"; then
        IFS='|' read -r _expiry_user expiry_date public_key <<< "$(grep -m1 -E "^${user}\|" "$EXPIRY_DB")" || true
        # Try to get IP from wg0.conf near the public key
        if [[ -n "$public_key" ]]; then
            client_ip=$(awk -v pk="$public_key" 'index($0,pk){ for(i=NR-1;i<=NR+5;i++){getline; if($0 ~ /AllowedIPs/) {print $3; exit}} }' "$WG_CONF" 2>/dev/null || true)
        fi
        echo "${public_key:-}|${client_ip:-}|${expiry_date:-}"
        return 0
    fi

    # Fallback: search wg0.conf by comment or by public key in config
    line_start=$(grep -n -m1 -E "^#\s+${user}(\s|$|[-(])" "$WG_CONF" | cut -d: -f1 || true)
    if [[ -n "$line_start" ]]; then
        # get public key and AllowedIPs within next 8 lines
        public_key=$(sed -n "$((line_start+1)),$((line_start+8))p" "$WG_CONF" | awk '/PublicKey/ {print $3; exit}')
        client_ip=$(sed -n "$((line_start+1)),$((line_start+8))p" "$WG_CONF" | awk '/AllowedIPs/ {print $3; exit}')
        echo "${public_key:-}|${client_ip:-}|"
        return 0
    fi

    # Another fallback: extract from client file
    if [[ -f "${CLIENT_DIR}/${user}.conf" ]]; then
        public_key=$(awk '/PublicKey/ {print $3; exit}' "${CLIENT_DIR}/${user}.conf" || true)
        client_ip=$(awk '/Address/ {print $3; exit}' "${CLIENT_DIR}/${user}.conf" || true)
        echo "${public_key:-}|${client_ip:-}|"
        return 0
    fi

    return 1
}

backup_config() {
    local backup_file="$BACKUP_DIR/wg0.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$WG_CONF" "$backup_file"
    log_info "Backup created: $backup_file"
    echo "$backup_file"
}

# ---------- Date Validation (YYYY-MM-DD) ----------
validate_date() {
    local date_str=$1
    if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "Invalid date format. Use YYYY-MM-DD"
        return 1
    fi
    if ! date -d "$date_str" >/dev/null 2>&1; then
        log_error "Invalid date: $date_str"
        return 1
    fi
    return 0
}

# ---------- Update expiry DB ----------
update_expiry_database() {
    local user=$1 new_expiry=$2 public_key=$3
    if [[ ! -f "$EXPIRY_DB" ]]; then
        touch "$EXPIRY_DB"
        chmod 600 "$EXPIRY_DB"
    fi
    # remove existing
    sed -i "/^${user}\|/d" "$EXPIRY_DB" || true
    echo "${user}|${new_expiry}|${public_key:-}" >> "$EXPIRY_DB"
    log_success "Expiry DB updated for $user -> $new_expiry"
}

# ---------- Update comment in wg0.conf ----------
update_config_comment() {
    local user=$1 new_expiry=$2 public_key=$3
    backup_config >/dev/null
    # find comment line matching user
    local line_num
    line_num=$(grep -n -m1 -E "^#\s+${user}(\s|$|[-(])" "$WG_CONF" | cut -d: -f1 || true)
    if [[ -n "$line_num" ]]; then
        sed -i "${line_num}s/.*/# ${user} (Exp: ${new_expiry})/" "$WG_CONF"
        log_info "Updated comment line for $user in wg0.conf"
        return 0
    fi
    # fallback: insert before public key line if public_key known
    if [[ -n "$public_key" ]]; then
        local key_line
        key_line=$(grep -n -m1 -F "PublicKey = ${public_key}" "$WG_CONF" | cut -d: -f1 || true)
        if [[ -n "$key_line" ]]; then
            sed -i "${key_line}i # ${user} (Exp: ${new_expiry})" "$WG_CONF"
            log_info "Inserted comment for $user based on public key"
            return 0
        fi
    fi
    log_warn "Could not update wg0.conf comment for $user (no matching line found)"
    return 1
}

# ---------- Apply config safely (wg syncconf via temp file) ----------
apply_config_safe() {
    local tmp_conf="/tmp/wg0-strip-$(date +%s).conf"
    if wg-quick strip wg0 > "$tmp_conf" 2>/dev/null && wg syncconf wg0 "$tmp_conf"; then
        rm -f "$tmp_conf"
        return 0
    else
        rm -f "$tmp_conf" 2>/dev/null || true
        return 1
    fi
}

# ---------- Renew user ----------
renew_user() {
    local user=$1 new_expiry=$2
    log_info "Renewing user: $user -> $new_expiry"

    local info public_key client_ip old_expiry
    info=$(get_user_info "$user") || { log_error "Cannot find info for $user"; return 1; }
    IFS='|' read -r public_key client_ip old_expiry <<< "$info"

    echo
    log_info "User: $user"
    echo -e "  🔑 PublicKey: ${public_key:-N/A}"
    echo -e "  📍 IP: ${client_ip:-N/A}"
    echo -e "  📅 Old expiry: ${old_expiry:-N/A}"
    echo -e "  📅 New expiry: ${new_expiry}"
    echo

    read -rp "Confirm renewal? (y/N): " confirm
    if ! [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Renewal cancelled"
        return 0
    fi

    # Update DB and config comment
    update_expiry_database "$user" "$new_expiry" "$public_key"
    if update_config_comment "$user" "$new_expiry" "$public_key"; then
        log_info "wg0.conf comment updated"
    else
        log_warn "wg0.conf comment not updated (but DB is updated)"
    fi

    # Apply without full restart if possible
    if systemctl is-active --quiet wg-quick@wg0; then
        if apply_config_safe; then
            log_success "WireGuard live reload applied"
        else
            log_warn "Live reload failed — restarting service..."
            if systemctl restart wg-quick@wg0; then
                log_success "WireGuard restarted"
            else
                log_error "Failed to restart WireGuard"
                return 1
            fi
        fi
    else
        log_warn "WireGuard service not running — skipping live reload"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RENEWED: ${user} (Old: ${old_expiry:-N/A}, New: ${new_expiry})" >> "$RENEW_LOG"
    log_success "User $user renewed successfully"
    return 0
}

# ---------- UI / Main ----------
main() {
    if ! validate_environment; then
        read -n 1 -s -r -p "Press any key to return..."
        clear; m-wg; return
    fi

    clear
    echo -e "${green}=========================================${nc}"
    echo -e "${blue}         🔄 Renew WireGuard User         ${nc}"
    echo -e "${green}=========================================${nc}"
    echo

    read -rp "Enter username to renew: " user
    if [[ -z "$user" ]]; then
        log_error "Username cannot be empty"
        read -n 1 -s -r -p "Press any key to continue..."
        clear; main; return
    fi

    if ! check_user_exists "$user"; then
        log_error "User '$user' not found"
        read -n 1 -s -r -p "Press any key to continue..."
        clear; main; return
    fi

    echo
    echo -e "${yellow}Enter new expiration date (YYYY-MM-DD):${nc}"
    read -rp "New expiration date: " new_expiry
    if [[ -z "$new_expiry" ]]; then
        log_error "New expiry cannot be empty"
        read -n 1 -s -r -p "Press any key to continue..."
        clear; main; return
    fi
    if ! validate_date "$new_expiry"; then
        read -n 1 -s -r -p "Press any key to continue..."
        clear; main; return
    fi

    if renew_user "$user" "$new_expiry"; then
        log_success "Renewal completed"
    else
        log_error "Renewal failed"
    fi

    read -n 1 -s -r -p "Press any key to return to menu..."
    clear; m-wg
}

main
