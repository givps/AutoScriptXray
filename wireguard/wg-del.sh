#!/bin/bash
# =========================================
# DELETE WIREGUARD USER + AUTO EXPIRE CLEANUP
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Config ----------
readonly WG_CONF="/etc/wireguard/wg0.conf"
readonly CLIENT_DIR="/etc/wireguard/clients"
readonly BACKUP_DIR="/etc/wireguard/backups"
readonly EXPIRY_DB="/etc/wireguard/user_expiry.db"
readonly LOG_DIR="/var/log/wireguard"
readonly LOG_FILE="$LOG_DIR/user-management.log"

# ---------- Helpers ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

# ---------- Validation ----------
validate_environment() {
    [[ -f "$WG_CONF" ]] || { log_error "Config not found: $WG_CONF"; exit 1; }
    mkdir -p "$CLIENT_DIR" "$BACKUP_DIR" "$LOG_DIR"
    chmod 700 "$LOG_DIR"
}

backup_config() {
    local backup_file="$BACKUP_DIR/wg0.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$WG_CONF" "$backup_file"
    log_info "Backup created: $backup_file"
}

# ---------- Delete a Specific User ----------
delete_user() {
    local user=$1
    local line_start line_end public_key client_config

    log_info "Searching for user: $user"

    # Cari baris komentar user (# user ... )
    line_start=$(grep -n -m1 -E "^# $user( |-|$)" "$WG_CONF" | cut -d: -f1)
    if [[ -z "$line_start" ]]; then
        log_error "User '$user' not found in wg0.conf"
        return 1
    fi

    # Ambil public key user
    public_key=$(awk "NR>$line_start && /PublicKey/{print \$3; exit}" "$WG_CONF")

    # Cari batas akhir blok peer berikutnya atau EOF
    line_end=$(awk -v start="$line_start" 'NR>start && /^\[Peer\]/{print NR-1; exit}' "$WG_CONF")
    [[ -z "$line_end" ]] && line_end=$(wc -l < "$WG_CONF")

    backup_config

    log_info "Deleting config lines $line_start to $line_end..."
    sed -i "${line_start},${line_end}d" "$WG_CONF"
    sed -i '/^$/N;/^\n$/D' "$WG_CONF"

    # Hapus file client
    client_config="$CLIENT_DIR/$user.conf"
    if [[ -f "$client_config" ]]; then
        local client_backup="$BACKUP_DIR/client_${user}_$(date +%Y%m%d_%H%M%S).conf"
        cp "$client_config" "$client_backup"
        rm -f "$client_config"
        log_info "Client config removed and backed up"
    fi

    # Hapus dari konfigurasi aktif (jika service aktif)
    if systemctl is-active --quiet wg-quick@wg0 && [[ -n "$public_key" ]]; then
        wg set wg0 peer "$public_key" remove 2>/dev/null || true
        log_info "Removed from active WireGuard session"
    fi

    # Hapus dari database expiry (jika ada)
    [[ -f "$EXPIRY_DB" ]] && sed -i "/^$user|/d" "$EXPIRY_DB"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DELETED: $user (PublicKey: ${public_key:-UNKNOWN})" >> "$LOG_FILE"
    log_success "User '$user' deleted successfully!"
    return 0
}

# ---------- Delete Expired Users ----------
delete_expired_users() {
    log_info "Checking expired users..."
    [[ -f "$EXPIRY_DB" ]] || { log_warn "No expiry database found."; return 0; }

    local today expired=0
    today=$(date +%Y-%m-%d)

    while IFS='|' read -r user expiry_date public_key; do
        [[ -z "$user" || -z "$expiry_date" ]] && continue
        if [[ $(date -d "$expiry_date" +%s) -lt $(date -d "$today" +%s) ]]; then
            log_warn "User '$user' expired ($expiry_date) → deleting..."
            delete_user "$user" && ((expired++))
        fi
    done < "$EXPIRY_DB"

    [[ $expired -eq 0 ]] && log_success "No expired users found" || log_success "Removed $expired expired users"
}

# ---------- List All Users ----------
list_all_users() {
    log_info "WireGuard users:"
    echo -e "${yellow}=========================================${nc}"
    local count=0 today=$(date +%Y-%m-%d)

    if [[ -f "$EXPIRY_DB" ]]; then
        while IFS='|' read -r user expiry_date public_key; do
            [[ -z "$user" ]] && continue
            local status="${green}Active${nc}"
            if [[ $(date -d "$expiry_date" +%s) -lt $(date -d "$today" +%s) ]]; then
                status="${red}Expired${nc}"
            fi
            echo -e " 👤 $user | 📅 Expiry: $expiry_date | $status"
            ((count++))
        done < "$EXPIRY_DB"
    fi

    # Tambahkan user tanpa expiry
    grep "^# " "$WG_CONF" | grep -v "Interface" | while read -r comment; do
        local uname
        uname=$(echo "$comment" | awk '{print $2}')
        grep -q "^$uname|" "$EXPIRY_DB" 2>/dev/null || {
            echo -e " 👤 $uname | 📅 Expiry: ${yellow}NOT SET${nc}"
            ((count++))
        }
    done

    [[ $count -eq 0 ]] && echo -e "${yellow}No users found${nc}"
    echo -e "${yellow}=========================================${nc}"
}

# ---------- Confirm Delete ----------
confirm_delete() {
    local user=$1
    echo
    log_warn "⚠️  You are about to delete user '$user'"
    echo -e "${red}This cannot be undone!${nc}"
    echo
    read -rp "Confirm delete (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]]
}

# ---------- Menu ----------
show_menu() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}     ⚙️ WireGuard User Management      ${nc}"
    echo -e "${red}=========================================${nc}"
    list_all_users
    echo
    echo -e " ${white}1${nc}) Delete specific user"
    echo -e " ${white}2${nc}) Auto-delete expired users"
    echo -e " ${white}3${nc}) Refresh user list"
    echo -e "${red}=========================================${nc}"
    echo -e " ${white}0${nc}) Back to main menu"
    echo -e " Press ${yellow}x${nc} or Ctrl+C to exit"
    echo -e "${red}=========================================${nc}"
}

# ---------- Main ----------
main() {
    validate_environment
    local opt restart_needed=false
    show_menu
    read -rp "Select option [0-3]: " opt

    case "$opt" in
        1)
            read -rp "Enter username: " user
            if [[ -n "$user" ]] && confirm_delete "$user"; then
                delete_user "$user" && restart_needed=true
            fi
            ;;
        2)
            delete_expired_users && restart_needed=true
            ;;
        3)
            read -n 1 -s -r -p "Press any key to continue..."
            main; return
            ;;
        0)
            clear; m-wg; return ;;
        *)
            log_error "Invalid option!"; sleep 1; main; return ;;
    esac

    if [[ "$restart_needed" == true ]]; then
        log_info "Reloading WireGuard..."
        if systemctl reload-or-restart wg-quick@wg0; then
            log_success "WireGuard reloaded successfully"
        else
            log_error "WireGuard reload failed!"
        fi
    fi

    read -n 1 -s -r -p "Press any key to return..."
    main
}

main
