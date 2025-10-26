#!/bin/bash
# =========================================
# DELETE WIREGUARD USER + AUTO EXPIRE CLEANUP - IMPROVED
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
readonly BACKUP_DIR="/etc/wireguard/backups"

# ---------- Functions ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

# ---------- Validation Functions ----------
validate_environment() {
    if [[ ! -f "$WG_CONF" ]]; then
        log_error "WireGuard configuration not found: $WG_CONF"
        exit 1
    fi
    
    if [[ ! -d "$CLIENT_DIR" ]]; then
        log_warn "Client directory not found, creating: $CLIENT_DIR"
        mkdir -p "$CLIENT_DIR"
    fi
    
    mkdir -p "$BACKUP_DIR"
}

backup_config() {
    local backup_file="$BACKUP_DIR/wg0.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$WG_CONF" "$backup_file"
    log_info "Config backed up to: $backup_file"
}

# ---------- Function: Delete Specific User ----------
delete_user() {
    local user=$1
    local line_start line_end peer_block public_key
    
    log_info "Searching for user: $user"
    
    # Find the comment line marking the user
    line_start=$(grep -n "^# $user\$" "$WG_CONF" | cut -d: -f1)
    
    if [[ -z "$line_start" ]]; then
        log_error "User '$user' not found in configuration!"
        return 1
    fi
    
    # Extract public key for verification
    public_key=$(sed -n "$((line_start+1)),$((line_start+10))p" "$WG_CONF" | grep "PublicKey" | awk '{print $3}')
    
    if [[ -z "$public_key" ]]; then
        log_warn "Could not extract public key for user '$user'"
    fi
    
    # Find the end of the peer block (next empty line or end of file)
    line_end=$((line_start + 1))
    while IFS= read -r line; do
        if [[ -z "$line" ]] || [[ "$line" =~ ^# ]] || [[ "$line" =~ ^\[Peer\] ]]; then
            break
        fi
        ((line_end++))
    done < <(tail -n +$((line_start + 2)) "$WG_CONF")
    
    # Create backup before modification
    backup_config
    
    # Remove the peer block
    log_info "Removing configuration lines $line_start to $line_end"
    sed -i "${line_start},${line_end}d" "$WG_CONF"
    
    # Remove client config file
    local client_config="$CLIENT_DIR/$user.conf"
    if [[ -f "$client_config" ]]; then
        # Backup client config before deletion
        local client_backup="$BACKUP_DIR/client_${user}_$(date +%Y%m%d_%H%M%S).conf"
        cp "$client_config" "$client_backup"
        rm -f "$client_config"
        log_info "Client config backed up and removed: $client_config"
    else
        log_warn "Client config file not found: $client_config"
    fi
    
    # Remove from running configuration if service is active
    if systemctl is-active --quiet wg-quick@wg0 && [[ -n "$public_key" ]]; then
        log_info "Removing peer from running configuration..."
        wg set wg0 peer "$public_key" remove
    fi
    
    log_success "User '$user' has been successfully deleted"
    
    # Log the deletion
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DELETED: $user (PublicKey: ${public_key:-UNKNOWN})" >> /var/log/wireguard/user-management.log
    
    return 0
}

# ---------- Function: Auto Delete Expired Users ----------
delete_expired_users() {
    log_info "Checking for expired WireGuard users..."
    
    local today expired_count=0
    today=$(date +%Y-%m-%d)
    
    # Check if expiry tracking file exists
    local expiry_file="/etc/wireguard/user_expiry.db"
    if [[ ! -f "$expiry_file" ]]; then
        log_warn "No expiry database found. Create users with expiry dates first."
        return 0
    fi
    
    # Process expiry database
    while IFS='|' read -r user expiry_date public_key; do
        if [[ -n "$user" && -n "$expiry_date" ]]; then
            if [[ "$expiry_date" < "$today" ]]; then
                log_warn "User '$user' expired on $expiry_date. Deleting..."
                if delete_user "$user"; then
                    # Remove from expiry database
                    sed -i "/^$user|/d" "$expiry_file"
                    ((expired_count++))
                fi
            fi
        fi
    done < "$expiry_file"
    
    if [[ $expired_count -eq 0 ]]; then
        log_success "No expired users found"
    else
        log_success "Cleaned up $expired_count expired users"
    fi
}

# ---------- Function: List All Users ----------
list_all_users() {
    log_info "Current WireGuard users:"
    echo -e "${yellow}=========================================${nc}"
    
    local user_count=0
    if [[ -f "/etc/wireguard/user_expiry.db" ]]; then
        while IFS='|' read -r user expiry_date public_key; do
            if [[ -n "$user" ]]; then
                local status="Active"
                if [[ "$expiry_date" < "$(date +%Y-%m-%d)" ]]; then
                    status="${red}EXPIRED${nc}"
                fi
                echo -e " 👤 $user | 📅 Expiry: $expiry_date | $status"
                ((user_count++))
            fi
        done < "/etc/wireguard/user_expiry.db"
    fi
    
    # Also show users from config file without expiry
    grep "^# " "$WG_CONF" | grep -v "^# \[Interface\]" | while read -r comment; do
        user=$(echo "$comment" | awk '{print $2}')
        if ! grep -q "^$user|" "/etc/wireguard/user_expiry.db" 2>/dev/null; then
            echo -e " 👤 $user | 📅 Expiry: ${yellow}NOT SET${nc}"
            ((user_count++))
        fi
    done
    
    if [[ $user_count -eq 0 ]]; then
        echo -e "${yellow}No users found${nc}"
    fi
    echo -e "${yellow}=========================================${nc}"
}

# ---------- Function: Confirm Deletion ----------
confirm_deletion() {
    local user=$1
    echo
    log_warn "⚠️  You are about to delete user: $user"
    echo -e "${red}This action cannot be undone!${nc}"
    echo
    read -rp "Are you sure? (y/N): " confirmation
    case "$confirmation" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_info "Deletion cancelled"
            return 1
            ;;
    esac
}

# ---------- Main Menu ----------
show_menu() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}    ⚙️  WireGuard User Management       ${nc}"
    echo -e "${red}=========================================${nc}"
    list_all_users
    echo
    echo -e " ${white}1${nc}) Delete a specific user"
    echo -e " ${white}2${nc}) Auto-delete expired users"
    echo -e " ${white}3${nc}) List all users with expiry"
    echo -e "${red}=========================================${nc}"
    echo -e " ${white}0${nc}) Back to main menu"
    echo -e " Press ${yellow}x${nc} or Ctrl+C to exit"
    echo -e "${red}=========================================${nc}"
}

# ---------- Main Execution ----------
main() {
    validate_environment
    
    local restart_needed=false
    local opt
    
    show_menu
    read -rp "Select an option [0-3]: " opt

    case "$opt" in
        1)
            read -rp "Enter username to delete: " user
            if [[ -n "$user" ]]; then
                if confirm_deletion "$user"; then
                    delete_user "$user" && restart_needed=true
                fi
            else
                log_error "Username cannot be empty"
            fi
            ;;
        2)
            if delete_expired_users; then
                restart_needed=true
            fi
            ;;
        3)
            # Just show the list and refresh menu
            read -n 1 -s -r -p "Press any key to continue..."
            main
            return
            ;;
        0)
            clear
            m-wg
            return
            ;;
        *)
            log_error "Invalid option!"
            sleep 1
            main
            return
            ;;
    esac

    # ---------- Restart WireGuard if needed ----------
    if [[ "$restart_needed" = true ]]; then
        log_info "Applying configuration changes..."
        if systemctl reload-or-restart wg-quick@wg0; then
            log_success "WireGuard service reconfigured successfully"
        else
            log_error "Failed to restart WireGuard service"
        fi
    fi

    read -n 1 -s -r -p "Press any key to return to menu..."
    main
}

# Run main function
main
