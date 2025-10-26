#!/bin/bash
# =========================================
# RENEW WIREGUARD USER - IMPROVED VERSION
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
readonly EXPIRY_DB="/etc/wireguard/user_expiry.db"
readonly LOG_DIR="/var/log/wireguard"

# ---------- Functions ----------
log_error() { echo -e "${red}❌ $1${nc}"; }
log_success() { echo -e "${green}✅ $1${nc}"; }
log_warn() { echo -e "${yellow}⚠️ $1${nc}"; }
log_info() { echo -e "${blue}ℹ️ $1${nc}"; }

# ---------- Validation Functions ----------
validate_environment() {
    if [[ ! -f "$WG_CONF" ]]; then
        log_error "WireGuard configuration not found: $WG_CONF"
        return 1
    fi
    
    if ! command -v wg >/dev/null 2>&1; then
        log_error "WireGuard is not installed!"
        return 1
    fi
    
    mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$CLIENT_DIR"
    return 0
}

check_user_exists() {
    local user=$1
    
    # Check in expiry database first
    if [[ -f "$EXPIRY_DB" ]] && grep -q "^$user|" "$EXPIRY_DB"; then
        return 0
    fi
    
    # Check in WireGuard config
    if grep -q "^# $user\$" "$WG_CONF"; then
        return 0
    fi
    
    # Check client config file
    if [[ -f "$CLIENT_DIR/$user.conf" ]]; then
        return 0
    fi
    
    return 1
}

get_user_info() {
    local user=$1
    local public_key client_ip expiry_date
    
    # Try to get from expiry database
    if [[ -f "$EXPIRY_DB" ]]; then
        IFS='|' read -r username expiry_date public_key <<< "$(grep "^$user|" "$EXPIRY_DB")"
        if [[ -n "$public_key" ]]; then
            # Get client IP from WireGuard config
            client_ip=$(grep -A5 "^# $user\$" "$WG_CONF" | grep AllowedIPs | awk '{print $3}')
            echo "$public_key|$client_ip|$expiry_date"
            return 0
        fi
    fi
    
    # Fallback: get from WireGuard config directly
    local line_start=$(grep -n "^# $user\$" "$WG_CONF" | cut -d: -f1)
    if [[ -n "$line_start" ]]; then
        public_key=$(sed -n "$((line_start+1)),$((line_start+5))p" "$WG_CONF" | grep PublicKey | awk '{print $3}')
        client_ip=$(sed -n "$((line_start+1)),$((line_start+5))p" "$WG_CONF" | grep AllowedIPs | awk '{print $3}')
        echo "$public_key|$client_ip|"
        return 0
    fi
    
    return 1
}

backup_config() {
    local backup_file="$BACKUP_DIR/wg0.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$WG_CONF" "$backup_file"
    log_info "Config backed up to: $backup_file"
    echo "$backup_file"
}

validate_date() {
    local date_str=$1
    local today=$(date +%Y-%m-%d)
    
    # Check if date is in valid format
    if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "Invalid date format! Use YYYY-MM-DD"
        return 1
    fi
    
    # Check if date is valid using date command
    if ! date -d "$date_str" >/dev/null 2>&1; then
        log_error "Invalid date: $date_str"
        return 1
    fi
    
    # Check if date is in the future
    if [[ "$date_str" < "$today" ]]; then
        log_warn "Warning: Date $date_str is in the past!"
        read -rp "Continue anyway? (y/N): " confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) ;;
            *) return 1 ;;
        esac
    fi
    
    return 0
}

update_expiry_database() {
    local user=$1
    local new_expiry=$2
    local public_key=$3
    
    # Create expiry database if it doesn't exist
    if [[ ! -f "$EXPIRY_DB" ]]; then
        touch "$EXPIRY_DB"
        chmod 600 "$EXPIRY_DB"
        log_info "Created expiry database: $EXPIRY_DB"
    fi
    
    # Remove existing entry if present
    if grep -q "^$user|" "$EXPIRY_DB"; then
        sed -i "/^$user|/d" "$EXPIRY_DB"
    fi
    
    # Add new entry
    echo "$user|$new_expiry|$public_key" >> "$EXPIRY_DB"
    log_success "Updated expiry database for user: $user"
}

update_config_comment() {
    local user=$1
    local new_expiry=$2
    local public_key=$3
    
    backup_config
    
    # Find and update the comment line
    local line_num=$(grep -n "^# $user" "$WG_CONF" | cut -d: -f1)
    if [[ -n "$line_num" ]]; then
        # Update existing comment
        sed -i "${line_num}s/.*/# $user (Exp: $new_expiry)/" "$WG_CONF"
    else
        # Find the public key line and add comment before it
        local key_line=$(grep -n "PublicKey = $public_key" "$WG_CONF" | cut -d: -f1)
        if [[ -n "$key_line" ]]; then
            sed -i "${key_line}i # $user (Exp: $new_expiry)" "$WG_CONF"
        else
            log_warn "Could not find public key in config, comment not updated"
            return 1
        fi
    fi
    
    return 0
}

# ---------- Main Renew Function ----------
renew_user() {
    local user=$1
    local new_expiry=$2
    
    log_info "Renewing user: $user"
    
    # Get user information
    local user_info
    user_info=$(get_user_info "$user")
    if [[ $? -ne 0 ]]; then
        log_error "Could not retrieve user information for: $user"
        return 1
    fi
    
    IFS='|' read -r public_key client_ip old_expiry <<< "$user_info"
    
    # Display current information
    echo
    log_info "User Details:"
    echo -e "  👤 Username: $user"
    echo -e "  🔑 Public Key: ${public_key:0:20}..."
    echo -e "  📍 IP Address: $client_ip"
    if [[ -n "$old_expiry" ]]; then
        echo -e "  📅 Current Expiry: $old_expiry"
    else
        echo -e "  📅 Current Expiry: ${yellow}Not set${nc}"
    fi
    echo -e "  📅 New Expiry: $new_expiry"
    echo
    
    # Confirm renewal
    read -rp "Confirm renewal? (y/N): " confirm
    case "$confirm" in
        [yY]|[yY][eE][sS])
            ;;
        *)
            log_info "Renewal cancelled"
            return 0
            ;;
    esac
    
    # Update expiry database
    update_expiry_database "$user" "$new_expiry" "$public_key"
    
    # Update config file comment
    if update_config_comment "$user" "$new_expiry" "$public_key"; then
        log_success "Configuration updated successfully"
    else
        log_warn "Could not update config comment, but expiry database was updated"
    fi
    
    # Apply changes without full restart if possible
    log_info "Applying configuration changes..."
    if systemctl is-active --quiet wg-quick@wg0; then
        if wg syncconf wg0 <(wg-quick strip wg0 2>/dev/null); then
            log_success "WireGuard configuration reloaded successfully"
        else
            log_warn "Live reload failed, restarting service..."
            if systemctl restart wg-quick@wg0; then
                log_success "WireGuard service restarted"
            else
                log_error "Failed to restart WireGuard service"
                return 1
            fi
        fi
    else
        log_warn "WireGuard service is not running"
    fi
    
    # Log the renewal
    local log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] RENEWED: $user (IP: $client_ip, Old: ${old_expiry:-N/A}, New: $new_expiry)"
    echo "$log_entry" >> "$LOG_DIR/user-renewals.log"
    
    log_success "User '$user' has been renewed successfully!"
    echo -e "  📅 New expiration date: ${green}$new_expiry${nc}"
    
    return 0
}

# ---------- Main Execution ----------
main() {
    # Validate environment
    if ! validate_environment; then
        read -n 1 -s -r -p "Press any key to return to menu..."
        clear
        m-wg
        return
    fi
    
    # Check if WireGuard service is active
    if ! systemctl is-active --quiet wg-quick@wg0; then
        log_warn "WireGuard service is not active"
        read -rp "Start it now? (Y/n): " start_service
        case "${start_service:-y}" in
            [yY]|[yY][eE][sS])
                if systemctl start wg-quick@wg0; then
                    log_success "WireGuard service started"
                    sleep 2
                else
                    log_error "Failed to start WireGuard service"
                    read -n 1 -s -r -p "Press any key to return to menu..."
                    clear
                    m-wg
                    return
                fi
                ;;
            *)
                log_info "Continuing without starting service..."
                ;;
        esac
    fi
    
    clear
    echo -e "${green}=========================================${nc}"
    echo -e "${blue}         🔄 Renew WireGuard User         ${nc}"
    echo -e "${green}=========================================${nc}"
    echo
    
    # Get username
    read -rp "Enter username to renew: " user
    if [[ -z "$user" ]]; then
        log_error "Username cannot be empty!"
        read -n 1 -s -r -p "Press any key to try again..."
        main
        return
    fi
    
    # Check if user exists
    if ! check_user_exists "$user"; then
        log_error "User '$user' not found!"
        read -n 1 -s -r -p "Press any key to try again..."
        main
        return
    fi
    
    # Get new expiry date
    echo
    echo -e "${yellow}Enter new expiration date:${nc}"
    echo -e "  Format: ${white}YYYY-MM-DD${nc}"
    echo -e "  Example: ${white}$(date -d "+30 days" +%Y-%m-%d)${nc} (30 days from now)"
    echo
    read -rp "New expiration date: " new_expiry
    
    if [[ -z "$new_expiry" ]]; then
        log_error "Expiration date cannot be empty!"
        read -n 1 -s -r -p "Press any key to try again..."
        main
        return
    fi
    
    # Validate date
    if ! validate_date "$new_expiry"; then
        read -n 1 -s -r -p "Press any key to try again..."
        main
        return
    fi
    
    # Perform renewal
    if renew_user "$user" "$new_expiry"; then
        echo
        echo -e "${green}=========================================${nc}"
        log_success "Renewal completed successfully!"
        echo -e "${green}=========================================${nc}"
    else
        echo
        echo -e "${red}=========================================${nc}"
        log_error "Renewal failed!"
        echo -e "${red}=========================================${nc}"
    fi
    
    read -n 1 -s -r -p "Press any key to return to menu..."
    clear
    m-wg
}

# Run main function
main
