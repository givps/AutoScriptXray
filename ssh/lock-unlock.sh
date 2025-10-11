#!/bin/bash
# =========================================
# USER LOCK & UNLOCK TOOL
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# Configuration
LOG_FILE="/var/log/user-management.log"

# Function to check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}Error: This script must be run as root!${nc}"
        exit 1
    fi
}

# Function to validate username format
validate_username() {
    local username="$1"
    
    if [ -z "$username" ]; then
        echo -e "${red}Error: Username cannot be empty!${nc}"
        return 1
    fi
    
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo -e "${red}Error: Invalid username format!${nc}"
        echo -e "${yellow}Username must start with a letter or underscore and contain only letters, numbers, hyphens, and underscores.${nc}"
        return 1
    fi
    
    return 0
}

# Function to display available users
display_available_users() {
    echo ""
    echo -e "${yellow}Recently active users:${nc}"
    echo -e "${cyan}$(last -20 | awk '{print $1}' | sort | uniq | grep -v "reboot" | grep -v "wtmp" | head -10)${nc}"
    echo ""
    echo -e "${yellow}System users (last 10):${nc}"
    echo -e "${cyan}$(cat /etc/passwd | cut -d: -f1 | sort | head -10)${nc}"
}

# Function to get user status
get_user_status() {
    local username="$1"
    if passwd -S "$username" 2>/dev/null | grep -q "PS"; then
        echo "unlocked"
    elif passwd -S "$username" 2>/dev/null | grep -q "LK"; then
        echo "locked"
    else
        echo "unknown"
    fi
}

# Function to log activity
log_activity() {
    local action="$1"
    local username="$2"
    local status="$3"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $action: user '$username' $status by $(whoami)" >> "$LOG_FILE"
}

# Function to lock user
lock_user() {
    local username="$1"
    
    echo ""
    echo -e "${yellow}Locking user: ${blue}$username${nc}"

    if passwd -l "$username" &>/dev/null; then
        sleep 1
        new_status=$(get_user_status "$username")
        
        clear
        echo ""
        echo -e "${red}=========================================${nc}"
        echo -e "${red}        USER LOCKED SUCCESSFULLY        ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "Username      : ${blue}$username${nc}"
        echo -e "User ID       : ${white}$(id -u "$username")${nc}"
        echo -e "Previous Status: ${yellow}$current_status${nc}"
        echo -e "Current Status : ${red}$new_status${nc}"
        echo -e "Access         : ${red}BLOCKED${nc}"
        echo -e "Date           : ${white}$(date)${nc}"
        echo ""
        
        if [[ "$new_status" == "locked" ]]; then
            echo -e "${red}✓ User account has been successfully locked${nc}"
            echo -e "${red}✓ The user can no longer login${nc}"
            log_activity "LOCK" "$username" "SUCCESS"
        else
            echo -e "${yellow}⚠ User lock command executed but status verification failed${nc}"
            log_activity "LOCK" "$username" "EXECUTED_BUT_UNVERIFIED"
        fi
    else
        echo -e "${red}Error: Failed to lock user '$username'${nc}"
        log_activity "LOCK" "$username" "FAILED"
        return 1
    fi
    return 0
}

# Function to unlock user
unlock_user() {
    local username="$1"
    
    echo ""
    echo -e "${yellow}Unlocking user: ${blue}$username${nc}"

    if passwd -u "$username" &>/dev/null; then
        sleep 1
        new_status=$(get_user_status "$username")
        
        clear
        echo ""
        echo -e "${green}=========================================${nc}"
        echo -e "${green}        USER UNLOCKED SUCCESSFULLY      ${nc}"
        echo -e "${green}=========================================${nc}"
        echo ""
        echo -e "Username      : ${blue}$username${nc}"
        echo -e "User ID       : ${white}$(id -u "$username")${nc}"
        echo -e "Previous Status: ${yellow}$current_status${nc}"
        echo -e "Current Status : ${green}$new_status${nc}"
        echo -e "Access         : ${green}RESTORED${nc}"
        echo -e "Date           : ${white}$(date)${nc}"
        echo ""
        
        if [[ "$new_status" == "unlocked" ]]; then
            echo -e "${green}✓ User account has been successfully unlocked${nc}"
            echo -e "${green}✓ The user can now login again${nc}"
            log_activity "UNLOCK" "$username" "SUCCESS"
        else
            echo -e "${yellow}⚠ User unlock command executed but status verification failed${nc}"
            log_activity "UNLOCK" "$username" "EXECUTED_BUT_UNVERIFIED"
        fi
    else
        echo -e "${red}Error: Failed to unlock user '$username'${nc}"
        log_activity "UNLOCK" "$username" "FAILED"
        return 1
    fi
    return 0
}

# Main script execution
clear

# Check root privileges
check_root

# Display header
echo -e "${yellow}=========================================${nc}"
echo -e "${yellow}         USER LOCK & UNLOCK TOOL        ${nc}"
echo -e "${yellow}=========================================${nc}"
echo ""
echo -e "${blue}What do you want to do?${nc}"
echo -e "  ${white}1${nc} Lock a user account"
echo -e "  ${white}2${nc} Unlock a user account"
echo -e "  ${white}3${nc} Check user status"
echo -e "  ${white}4${nc} Exit"
echo ""
read -p "Select option [1-4]: " option

case $option in
    1)
        action="lock"
        action_color="${red}"
        ;;
    2)
        action="unlock"
        action_color="${green}"
        ;;
    3)
        action="status"
        action_color="${yellow}"
        ;;
    4)
        echo "Goodbye!"
        exit 0
        ;;
    *)
        echo -e "${red}Invalid option!${nc}"
        exit 1
        ;;
esac

clear
echo -e "${yellow}=========================================${nc}"
echo -e "${action_color}          USER ${action^^} TOOL           ${nc}"
echo -e "${yellow}=========================================${nc}"
echo ""

# Display recent users
display_available_users
echo ""

# Input username
read -p "Input USERNAME to $action: " username

# Validate input
if ! validate_username "$username"; then
    exit 1
fi

# Check if user exists
if ! id "$username" &>/dev/null; then
    echo -e "${red}Error: Username '${username}' not found in your server.${nc}"
    display_available_users
    exit 1
fi

# Get current user info
user_id=$(id -u "$username")
user_home=$(eval echo ~$username 2>/dev/null || echo "unknown")
current_status=$(get_user_status "$username")

# Display user information
echo ""
echo -e "${blue}User Information:${nc}"
echo -e "  Username : ${cyan}$username${nc}"
echo -e "  User ID  : ${white}$user_id${nc}"
echo -e "  Home Dir : ${white}$user_home${nc}"
echo -e "  Status   : ${yellow}$current_status${nc}"
echo ""

# Handle different actions
case $action in
    "lock")
        # Check if user is already locked
        if [[ "$current_status" == "locked" ]]; then
            echo -e "${yellow}User '${username}' is already locked.${nc}"
            echo ""
            read -p "Do you want to continue anyway? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Operation cancelled."
                log_activity "LOCK_ATTEMPT" "$username" "CANCELLED_ALREADY_LOCKED"
                exit 0
            fi
        fi

        # Confirm lock action
        echo -e "${red}WARNING: This will prevent user '${username}' from logging in!${nc}"
        echo ""
        read -p "Are you sure you want to lock this user? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            log_activity "LOCK_ATTEMPT" "$username" "CANCELLED"
            exit 0
        fi

        lock_user "$username"
        ;;

    "unlock")
        # Check if user is already unlocked
        if [[ "$current_status" == "unlocked" ]]; then
            echo -e "${yellow}User '${username}' is already unlocked.${nc}"
            echo ""
            read -p "Do you want to continue anyway? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Operation cancelled."
                log_activity "UNLOCK_ATTEMPT" "$username" "CANCELLED_ALREADY_UNLOCKED"
                exit 0
            fi
        fi

        # Confirm unlock action
        echo -e "${green}This will allow user '${username}' to login again.${nc}"
        echo ""
        read -p "Are you sure you want to unlock this user? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            log_activity "UNLOCK_ATTEMPT" "$username" "CANCELLED"
            exit 0
        fi

        unlock_user "$username"
        ;;

    "status")
        echo -e "${yellow}=========================================${nc}"
        echo -e "${yellow}           USER STATUS REPORT           ${nc}"
        echo -e "${yellow}=========================================${nc}"
        echo ""
        echo -e "Username      : ${cyan}$username${nc}"
        echo -e "User ID       : ${white}$user_id${nc}"
        echo -e "Home Directory: ${white}$user_home${nc}"
        echo -e "Login Shell   : ${white}$(getent passwd "$username" | cut -d: -f7)${nc}"
        echo -e "Account Status: ${yellow}$current_status${nc}"
        echo ""
        
        # Show additional info based on status
        if [[ "$current_status" == "locked" ]]; then
            echo -e "${red}⛔ This account is currently LOCKED${nc}"
            echo -e "${red}   The user cannot login${nc}"
        elif [[ "$current_status" == "unlocked" ]]; then
            echo -e "${green}✅ This account is currently UNLOCKED${nc}"
            echo -e "${green}   The user can login normally${nc}"
        else
            echo -e "${yellow}⚠️  Unable to determine account status${nc}"
        fi
        
        # Show last login
        last_login=$(last -n 1 "$username" 2>/dev/null | head -1)
        if [[ -n "$last_login" ]]; then
            echo -e "Last Login   : ${white}$last_login${nc}"
        else
            echo -e "Last Login   : ${white}Never logged in${nc}"
        fi
        
        echo -e "${yellow}=========================================${nc}"
        log_activity "STATUS_CHECK" "$username" "VIEWED"
        ;;
esac

echo ""
read -n 1 -s -r -p "Press any key to continue..."
m-sshovpn
