#!/bin/bash
# ==========================================
# Renew VLess Account - Improved Version
# ==========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

# Getting system info
get_system_ip() {
    MYIP=$(curl -s --connect-timeout 3 -4 ifconfig.co 2>/dev/null || \
           curl -s --connect-timeout 3 -4 ifconfig.me 2>/dev/null || \
           curl -s --connect-timeout 3 -4 icanhazip.com 2>/dev/null || \
           echo "unknown")
    echo "$MYIP"
}

get_domain() {
    domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || \
             cat /etc/xray/domain 2>/dev/null || \
             cat /root/domain 2>/dev/null || \
             echo "unknown")
    echo "$domain"
}

MYIP=$(get_system_ip)
domain=$(get_domain)

clear

# Function to count VLess users
count_vless_users() {
    local config_file="/usr/local/etc/xray/config.json"
    if [[ ! -f "$config_file" ]]; then
        echo "0"
        return 1
    fi
    # More specific pattern to match only VLess user entries
    grep -c -E "^### [a-zA-Z0-9_-]+ [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$config_file" 2>/dev/null || echo "0"
}

# Function to sanitize username
sanitize_username() {
    local username="$1"
    # Remove potentially dangerous characters and limit length
    username=$(echo "$username" | sed 's/[^a-zA-Z0-9_-]//g')
    username="${username:0:50}"
    echo "$username"
}

# Function to validate date format
validate_date() {
    local date_str="$1"
    
    # Check format YYYY-MM-DD
    if [[ ! "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi
    
    # Extract components
    local year="${date_str:0:4}"
    local month="${date_str:5:2}"
    local day="${date_str:8:2}"
    
    # Remove leading zeros for arithmetic
    month=$((10#$month))
    day=$((10#$day))
    
    # Basic range validation
    if [[ $month -lt 1 || $month -gt 12 ]]; then
        return 1
    fi
    
    if [[ $day -lt 1 || $day -gt 31 ]]; then
        return 1
    fi
    
    # Use date command for final validation
    if date -d "$date_str" "+%Y-%m-%d" >/dev/null 2>&1; then
        if [[ $(date -d "$date_str" "+%Y-%m-%d" 2>/dev/null) == "$date_str" ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to backup config
backup_config() {
    local config_file="/usr/local/etc/xray/config.json"
    local backup_dir="/usr/local/etc/xray/backups"
    local max_backups=5
    
    if [[ ! -f "$config_file" ]]; then
        echo "error"
        return 1
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir" 2>/dev/null
    
    local backup_file="$backup_dir/config.json.backup.$(date +%Y%m%d%H%M%S)"
    local temp_backup=$(mktemp)
    
    # Copy through temp file for safety
    if cp "$config_file" "$temp_backup" 2>/dev/null && \
       cp "$temp_backup" "$backup_file" 2>/dev/null; then
        rm -f "$temp_backup"
        
        # Clean up old backups (keep only latest max_backups)
        ls -t "$backup_dir"/config.json.backup.* 2>/dev/null | tail -n +$((max_backups + 1)) | while read -r old_backup; do
            rm -f "$old_backup" 2>/dev/null
        done
        
        echo "$backup_file"
        return 0
    else
        rm -f "$temp_backup" 2>/dev/null
        echo "error"
        return 1
    fi
}

# Function to restore config
restore_config() {
    local backup_file="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ -f "$backup_file" && -f "$config_file" ]]; then
        local temp_file=$(mktemp)
        if cp "$backup_file" "$temp_file" 2>/dev/null && \
           python3 -m json.tool "$temp_file" >/dev/null 2>&1; then
            cp "$temp_file" "$config_file"
            chmod 644 "$config_file"
            rm -f "$temp_file" "$backup_file" 2>/dev/null
            return 0
        else
            rm -f "$temp_file" 2>/dev/null
            return 1
        fi
    fi
    return 1
}

# Function to restart Xray service safely
restart_xray_service() {
    echo -e "${yellow}Restarting Xray service...${nc}"
    
    # Check if service exists and is active
    if ! systemctl is-active xray >/dev/null 2>&1; then
        echo -e "${red}Error: Xray service is not running${nc}"
        return 1
    fi
    
    # Validate config before restart
    if ! python3 -m json.tool /usr/local/etc/xray/config.json >/dev/null 2>&1; then
        echo -e "${red}Error: Invalid JSON configuration - cannot restart service${nc}"
        return 1
    fi
    
    if systemctl restart xray 2>/dev/null; then
        # Wait a moment for service to stabilize
        sleep 3
        
        # Verify service is running
        if systemctl is-active xray >/dev/null 2>&1; then
            echo -e "${green}✓ Xray service restarted successfully${nc}"
            return 0
        else
            echo -e "${red}Error: Xray service failed to start after restart${nc}"
            return 1
        fi
    else
        echo -e "${red}Error: Failed to restart Xray service${nc}"
        return 1
    fi
}

# Function to update expiry
update_expiry() {
    local user="$1"
    local old_exp="$2"
    local new_exp="$3"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${red}Error: Config file not found${nc}" >&2
        return 1
    fi
    
    if [[ ! -r "$config_file" ]]; then
        echo -e "${red}Error: Cannot read config file${nc}" >&2
        return 1
    fi
    
    if [[ ! -w "$config_file" ]]; then
        echo -e "${red}Error: Cannot write to config file${nc}" >&2
        return 1
    fi
    
    # Verify the user exists with old expiry
    if ! grep -q "^### $user $old_exp$" "$config_file"; then
        echo -e "${red}Error: User '$user' with expiry '$old_exp' not found${nc}" >&2
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Update expiry date using sed
    if sed "s/^### $user $old_exp$/### $user $new_exp/g" "$config_file" > "$temp_file" 2>/dev/null; then
        # Verify the update worked
        if grep -q "^### $user $new_exp$" "$temp_file"; then
            # Verify JSON validity
            if python3 -m json.tool "$temp_file" > /dev/null 2>&1; then
                # Create one more backup before final overwrite
                local final_backup="${config_file}.before_final_update"
                cp "$config_file" "$final_backup" 2>/dev/null
                
                if cp "$temp_file" "$config_file" 2>/dev/null; then
                    chmod 644 "$config_file"
                    rm -f "$temp_file" "$final_backup" 2>/dev/null
                    return 0
                else
                    # Restore from final backup if copy failed
                    cp "$final_backup" "$config_file" 2>/dev/null
                    rm -f "$temp_file" "$final_backup" 2>/dev/null
                    echo -e "${red}Error: Failed to update config file${nc}" >&2
                    return 1
                fi
            else
                rm -f "$temp_file" 2>/dev/null
                echo -e "${red}Error: Resulting config has invalid JSON syntax${nc}" >&2
                return 1
            fi
        else
            rm -f "$temp_file" 2>/dev/null
            echo -e "${red}Error: Failed to update user expiry in config${nc}" >&2
            return 1
        fi
    else
        rm -f "$temp_file" 2>/dev/null
        echo -e "${red}Error: Failed to process config file${nc}" >&2
        return 1
    fi
}

# Function to log actions
log_action() {
    local action="$1"
    local user="$2"
    local details="$3"
    local status="$4"
    local log_file="/var/log/xray-renewals.log"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] $action - User: $user - $details - Status: $status - IP: ${MYIP}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")" 2>/dev/null
    
    echo "$log_entry" >> "$log_file" 2>/dev/null
    
    # Also log to system logger if available
    if command -v logger >/dev/null 2>&1; then
        logger -t "xray-renew" "$log_entry"
    fi
}

# Function to get user expiry
get_user_expiry() {
    local user="$1"
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo ""
        return 1
    fi
    
    grep -E "^### $user " "$config_file" | head -1 | awk '{print $3}'
}

# Function to display users with better formatting
display_users() {
    local config_file="/usr/local/etc/xray/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # Use awk for more reliable parsing
    awk '/^### [a-zA-Z0-9_-]+ [0-9]{4}-[0-9]{2}-[0-9]{2}$/ {
        username = $2
        expiry = $3
        printf "  %-18s %s\n", username, expiry
    }' "$config_file" | sort -k2
}

# Function to update client files
update_client_files() {
    local user="$1"
    local old_exp="$2"
    local new_exp="$3"
    
    # Update text config file
    if [[ -f "/home/vps/public_html/vless-$user.txt" ]]; then
        sed -i "s/Expired On  : $old_exp/Expired On  : $new_exp/g" "/home/vps/public_html/vless-$user.txt" 2>/dev/null
        sed -i "s/Expiry: $old_exp/Expiry: $new_exp/g" "/home/vps/public_html/vless-$user.txt" 2>/dev/null
        sed -i "s/# Generated: .*/# Generated: $(date)/g" "/home/vps/public_html/vless-$user.txt" 2>/dev/null
    fi
    
    # Update JSON config file
    if [[ -f "/home/vps/public_html/vless-$user.json" ]]; then
        sed -i "s/\"expiry\": \"$old_exp\"/\"expiry\": \"$new_exp\"/g" "/home/vps/public_html/vless-$user.json" 2>/dev/null
    fi
}

# Main script execution
main() {
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           Renew VLess Account         ${nc}"
    echo -e "${red}=========================================${nc}"

    # Check if config file exists
    if [[ ! -f "/usr/local/etc/xray/config.json" ]]; then
        echo -e "${red}Error: Xray config file not found!${nc}"
        echo -e "${yellow}Expected location: /usr/local/etc/xray/config.json${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 1
    fi

    NUMBER_OF_CLIENTS=$(count_vless_users)

    if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
        echo ""
        echo -e "${yellow}You have no existing VLess clients!${nc}"
        echo ""
        echo -e "${red}=========================================${nc}"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 0
    fi

    # Display current users
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           Renew VLess Account         ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${green}  Username           Expired Date${nc}"
    echo -e "${red}=========================================${nc}"

    if ! display_users; then
        echo -e "${red}Error: Failed to display users${nc}"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 1
    fi

    echo -e "${red}=========================================${nc}"
    echo -e "${yellow}Total Users: $NUMBER_OF_CLIENTS${nc}"
    echo ""
    echo -e "${blue}Enter username to renew${nc}"
    echo -e "${yellow}• [NOTE] Press Enter without username to cancel${nc}"
    echo -e "${red}=========================================${nc}"

    read -rp "Input Username : " user_input

    # Check if user input is empty
    if [[ -z "$user_input" ]]; then
        echo -e "${yellow}Operation cancelled${nc}"
        log_action "RENEW_CANCELLED" "none" "User input empty" "CANCELLED"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 0
    fi

    # Sanitize username
    user=$(sanitize_username "$user_input")

    # Validate user exists
    current_exp=$(get_user_expiry "$user")
    if [[ -z "$current_exp" ]]; then
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}           Renew VLess Account         ${nc}"
        echo -e "${red}=========================================${nc}"
        echo -e "${red}Error: User '$user' not found!${nc}"
        echo ""
        echo -e "${yellow}Available users:${nc}"
        display_users
        echo -e "${red}=========================================${nc}"
        log_action "RENEW_FAILED" "$user" "User not found" "FAILED"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 1
    fi

    # Validate current expiry date format
    if ! validate_date "$current_exp"; then
        echo -e "${red}Error: Invalid current expiry date format: $current_exp${nc}"
        echo -e "${yellow}Please check the config file manually${nc}"
        log_action "RENEW_FAILED" "$user" "Invalid current expiry: $current_exp" "FAILED"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 1
    fi

    # Get renewal days with validation
    while true; do
        echo ""
        read -p "Extend for (days): " masaaktif
        
        # Validate input is numeric and within reasonable range
        if [[ "$masaaktif" =~ ^[0-9]+$ ]] && [ "$masaaktif" -gt 0 ] && [ "$masaaktif" -le 3650 ]; then
            break
        else
            echo -e "${red}Error: Please enter a valid number of days (1-3650)${nc}"
        fi
    done

    # Calculate new expiry date
    now=$(date +%Y-%m-%d)
    current_epoch=$(date -d "$current_exp" +%s 2>/dev/null)
    now_epoch=$(date -d "$now" +%s)

    # Handle expired accounts - if current expiry is in past, extend from today
    if [[ $current_epoch -lt $now_epoch ]]; then
        days_remaining=0
        new_exp=$(date -d "$now + $masaaktif days" +"%Y-%m-%d")
        echo -e "${yellow}Note: Account was expired. Renewing from today.${nc}"
    else
        days_remaining=$(( (current_epoch - now_epoch) / 86400 ))
        total_days=$((days_remaining + masaaktif))
        new_exp=$(date -d "$now + $total_days days" +"%Y-%m-%d")
    fi

    # Validate new expiry date
    if ! validate_date "$new_exp"; then
        echo -e "${red}Error: Failed to calculate valid new expiry date${nc}"
        log_action "RENEW_FAILED" "$user" "Invalid new expiry calculation: $new_exp" "FAILED"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 1
    fi

    # Display renewal summary
    echo ""
    echo -e "${blue}Renewal Summary:${nc}"
    echo -e "  • User          : $user"
    echo -e "  • Current Expiry: $current_exp"
    echo -e "  • Days Added    : $masaaktif"
    echo -e "  • New Expiry    : $new_exp"
    if [[ $days_remaining -gt 0 ]]; then
        echo -e "  • Days Remaining: $days_remaining → $((days_remaining + masaaktif))"
    fi
    echo ""

    # Confirm renewal
    read -rp "Confirm renewal? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${yellow}Renewal cancelled${nc}"
        log_action "RENEW_CANCELLED" "$user" "User cancelled confirmation" "CANCELLED"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 0
    fi

    # Backup config before modification
    echo -e "${yellow}Creating backup...${nc}"
    backup_file=$(backup_config)

    if [[ "$backup_file" == "error" ]]; then
        echo -e "${red}Error: Failed to create backup!${nc}"
        log_action "RENEW_FAILED" "$user" "Backup creation failed" "FAILED"
        read -n 1 -s -r -p "Press any key to back on menu"
        m-vless 2>/dev/null || exit 1
    else
        echo -e "${green}✓ Backup created: $(basename "$backup_file")${nc}"
    fi

    # Update expiry date in config
    echo -e "${yellow}Updating expiry date...${nc}"
    if update_expiry "$user" "$current_exp" "$new_exp"; then
        # Restart Xray service
        if restart_xray_service; then
            # Update client config files
            echo -e "${yellow}Updating client files...${nc}"
            update_client_files "$user" "$current_exp" "$new_exp"
            
            # Display success message
            clear
            echo -e "${red}=========================================${nc}"
            echo -e "${blue}           Renew VLess Account         ${nc}"
            echo -e "${red}=========================================${nc}"
            echo -e "${green}✓ VLess Account Successfully Renewed${nc}"
            echo ""
            echo -e "${blue}Details:${nc}"
            echo -e "  • Client Name    : $user"
            echo -e "  • Old Expiry     : $current_exp"
            echo -e "  • New Expiry     : $new_exp"
            echo -e "  • Days Added     : $masaaktif"
            if [[ $days_remaining -gt 0 ]]; then
                echo -e "  • Days Remaining : $days_remaining → $((days_remaining + masaaktif))"
            fi
            echo ""
            echo -e "${green}Service restarted successfully${nc}"
            echo -e "${red}=========================================${nc}"
            
            # Clean up backup file
            rm -f "$backup_file" 2>/dev/null
            
            # Log the successful renewal
            log_action "RENEW_SUCCESS" "$user" "From $current_exp to $new_exp (+$masaaktif days)" "SUCCESS"
            
        else
            echo -e "${red}Error: Failed to restart Xray service${nc}"
            echo -e "${yellow}Restoring backup config...${nc}"
            if restore_config "$backup_file"; then
                echo -e "${green}✓ Backup restored successfully${nc}"
                # Try to restart with restored config
                systemctl restart xray >/dev/null 2>&1
            else
                echo -e "${red}Error: Failed to restore backup! Manual intervention required.${nc}"
            fi
            log_action "RENEW_FAILED" "$user" "Service restart failed" "FAILED"
        fi
    else
        echo -e "${red}Error: Failed to update expiry date${nc}"
        echo -e "${yellow}Restoring backup config...${nc}"
        if restore_config "$backup_file"; then
            echo -e "${green}✓ Backup restored successfully${nc}"
            echo -e "${red}No changes were made${nc}"
        else
            echo -e "${red}Error: Failed to restore backup! Manual intervention required.${nc}"
        fi
        log_action "RENEW_FAILED" "$user" "Expiry update failed" "FAILED"
    fi

    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-vless 2>/dev/null || exit 0
}

# Run main function
main "$@"
