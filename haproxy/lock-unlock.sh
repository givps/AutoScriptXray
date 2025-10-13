#!/bin/bash
# =========================================
# USER LOCK & UNLOCK TOOL - HAPROXY WEBSOCKET VERSION
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

# Function to display available SSH users (HAProxy WS specific)
display_available_users() {
    echo ""
    echo -e "${yellow}📋 SSH & WebSocket Users:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    total_users=0
    locked_users=0
    
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read user; do
        if [ "$user" != "sync" ] && [ "$user" != "halt" ]; then
            ((total_users++))
            status=$(get_user_status "$user")
            
            if [ "$status" = "locked" ]; then
                ((locked_users++))
                echo -e " ${red}🔒 $user${nc} - ${red}LOCKED${nc}"
            else
                # Check if user is currently connected
                connections=$(who | grep "^$user" | wc -l)
                if [ $connections -gt 0 ]; then
                    echo -e " ${green}🟢 $user${nc} - ${green}ONLINE ($connections)${nc}"
                else
                    echo -e " ${white}⚪ $user${nc} - ${white}OFFLINE${nc}"
                fi
            fi
        fi
    done
    
    echo -e "${blue}=========================================${nc}"
    echo -e "Total Users  : ${white}$total_users${nc}"
    echo -e "Locked Users : ${red}$locked_users${nc}"
    echo -e "Active Users : ${green}$((total_users - locked_users))${nc}"
    echo ""
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

# Function to kill user connections (HAProxy WS specific)
kill_user_connections() {
    local username="$1"
    local action="$2"
    
    echo -e "${yellow}🔌 Terminating user connections...${nc}"
    
    # Kill SSH processes
    pkill -9 -u "$username" 2>/dev/null
    
    # Kill any remaining SSH sessions
    ps aux | grep "^$username" | grep -E "ssh" | awk '{print $2}' | xargs kill -9 2>/dev/null
    
    # Kill WebSocket connections by terminating their processes
    netstat -tnp 2>/dev/null | grep -E ':1443|:1444' | grep ESTABLISHED | while read conn; do
        pid=$(echo "$conn" | awk '{print $7}' | cut -d'/' -f1)
        process_user=$(ps -o user= -p "$pid" 2>/dev/null)
        if [ "$process_user" = "$username" ]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done
    
    echo -e "${green}✓ All connections terminated for $username${nc}"
}

# Function to lock user (HAProxy WS enhanced)
lock_user() {
    local username="$1"
    
    echo ""
    echo -e "${yellow}🔒 Locking user: ${blue}$username${nc}"

    # Kill all active connections first
    kill_user_connections "$username" "lock"
    
    # Lock the user account
    if passwd -l "$username" &>/dev/null; then
        sleep 1
        new_status=$(get_user_status "$username")
        
        # Update HAProxy configuration if needed
        if [ -f "/etc/haproxy/haproxy.cfg" ]; then
            echo -e "${yellow}🔄 Updating HAProxy configuration...${nc}"
            # Add user to blocked list or comment out specific rules
            sed -i "/### $username ###/d" /etc/haproxy/haproxy.cfg 2>/dev/null
            systemctl reload haproxy 2>/dev/null
        fi
        
        clear
        echo ""
        echo -e "${red}=========================================${nc}"
        echo -e "${red}        USER LOCKED SUCCESSFULLY        ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "Username       : ${blue}$username${nc}"
        echo -e "User ID        : ${white}$(id -u "$username")${nc}"
        echo -e "Previous Status: ${yellow}$current_status${nc}"
        echo -e "Current Status : ${red}$new_status${nc}"
        echo -e "Access         : ${red}BLOCKED${nc}"
        echo -e "Services       : ${red}SSH & WebSocket${nc}"
        echo -e "Date           : ${white}$(date)${nc}"
        echo ""
        
        if [[ "$new_status" == "locked" ]]; then
            echo -e "${red}✅ User account has been successfully locked${nc}"
            echo -e "${red}✅ All active connections terminated${nc}"
            echo -e "${red}✅ User can no longer login via SSH or WebSocket${nc}"
            log_activity "LOCK" "$username" "SUCCESS"
        else
            echo -e "${yellow}⚠️ User lock command executed but status verification failed${nc}"
            log_activity "LOCK" "$username" "EXECUTED_BUT_UNVERIFIED"
        fi
    else
        echo -e "${red}❌ Error: Failed to lock user '$username'${nc}"
        log_activity "LOCK" "$username" "FAILED"
        return 1
    fi
    return 0
}

# Function to unlock user (HAProxy WS enhanced)
unlock_user() {
    local username="$1"
    
    echo ""
    echo -e "${yellow}🔓 Unlocking user: ${blue}$username${nc}"

    if passwd -u "$username" &>/dev/null; then
        sleep 1
        new_status=$(get_user_status "$username")
        
        # Update HAProxy configuration if needed
        if [ -f "/etc/haproxy/haproxy.cfg" ]; then
            echo -e "${yellow}🔄 Updating HAProxy configuration...${nc}"
            # Remove user from blocked list
            sed -i "/### BLOCKED $username ###/d" /etc/haproxy/haproxy.cfg 2>/dev/null
            systemctl reload haproxy 2>/dev/null
        fi
        
        clear
        echo ""
        echo -e "${green}=========================================${nc}"
        echo -e "${green}        USER UNLOCKED SUCCESSFULLY      ${nc}"
        echo -e "${green}=========================================${nc}"
        echo ""
        echo -e "Username       : ${blue}$username${nc}"
        echo -e "User ID        : ${white}$(id -u "$username")${nc}"
        echo -e "Previous Status: ${yellow}$current_status${nc}"
        echo -e "Current Status : ${green}$new_status${nc}"
        echo -e "Access         : ${green}RESTORED${nc}"
        echo -e "Services       : ${green}SSH & WebSocket${nc}"
        echo -e "Date           : ${white}$(date)${nc}"
        echo ""
        
        if [[ "$new_status" == "unlocked" ]]; then
            echo -e "${green}✅ User account has been successfully unlocked${nc}"
            echo -e "${green}✅ User can now login via SSH and WebSocket${nc}"
            echo -e "${green}✅ All service restrictions removed${nc}"
            log_activity "UNLOCK" "$username" "SUCCESS"
        else
            echo -e "${yellow}⚠️ User unlock command executed but status verification failed${nc}"
            log_activity "UNLOCK" "$username" "EXECUTED_BUT_UNVERIFIED"
        fi
    else
        echo -e "${red}❌ Error: Failed to unlock user '$username'${nc}"
        log_activity "UNLOCK" "$username" "FAILED"
        return 1
    fi
    return 0
}

# Function to show detailed user status
show_detailed_status() {
    local username="$1"
    
    echo -e "${yellow}=========================================${nc}"
    echo -e "${yellow}           USER STATUS REPORT           ${nc}"
    echo -e "${yellow}=========================================${nc}"
    echo ""
    echo -e "Username       : ${cyan}$username${nc}"
    echo -e "User ID        : ${white}$user_id${nc}"
    echo -e "Home Directory : ${white}$user_home${nc}"
    echo -e "Login Shell    : ${white}$(getent passwd "$username" | cut -d: -f7)${nc}"
    echo -e "Account Status : ${yellow}$current_status${nc}"
    echo ""
    
    # Connection information
    echo -e "${blue}🌐 Connection Status:${nc}"
    ssh_connections=$(who | grep "^$username" | wc -l)
    ws_connections=$(netstat -tnp 2>/dev/null | grep -E ':1443|:1444' | grep ESTABLISHED | while read conn; do
        pid=$(echo "$conn" | awk '{print $7}' | cut -d'/' -f1)
        process_user=$(ps -o user= -p "$pid" 2>/dev/null)
        if [ "$process_user" = "$username" ]; then
            echo "found"
        fi
    done | wc -l)
    
    echo -e "SSH Connections : ${white}$ssh_connections${nc}"
    echo -e "WS Connections  : ${white}$ws_connections${nc}"
    echo -e "Total Active    : ${white}$((ssh_connections + ws_connections))${nc}"
    
    # Service access
    echo -e "${blue}🔧 Service Access:${nc}"
    if [[ "$current_status" == "locked" ]]; then
        echo -e "SSH Access      : ${red}❌ BLOCKED${nc}"
        echo -e "WebSocket Access: ${red}❌ BLOCKED${nc}"
        echo -e "Overall Access  : ${red}⛔ COMPLETELY LOCKED${nc}"
    else
        echo -e "SSH Access      : ${green}✅ ALLOWED${nc}"
        echo -e "WebSocket Access: ${green}✅ ALLOWED${nc}"
        echo -e "Overall Access  : ${green}🟢 FULL ACCESS${nc}"
    fi
    
    # Last login information
    echo -e "${blue}📅 Last Activity:${nc}"
    last_login=$(last -n 1 "$username" 2>/dev/null | head -1)
    if [[ -n "$last_login" && ! "$last_login" =~ "never logged in" ]]; then
        echo -e "Last Login     : ${white}$last_login${nc}"
    else
        echo -e "Last Login     : ${white}Never logged in${nc}"
    fi
    
    # Account expiry
    expiry_info=$(chage -l "$username" 2>/dev/null | grep "Account expires")
    userexp=$(echo "$expiry_info" | awk -F": " '{print $2}')
    if [ "$userexp" != "never" ] && [ -n "$userexp" ]; then
        echo -e "Account Expires: ${yellow}$userexp${nc}"
    else
        echo -e "Account Expires: ${green}Never${nc}"
    fi
    
    echo -e "${yellow}=========================================${nc}"
}

# Main script execution
clear

# Check root privileges
check_root

# Display header
echo -e "${yellow}=========================================${nc}"
echo -e "${blue}    USER LOCK & UNLOCK - HAProxy WS      ${nc}"
echo -e "${yellow}=========================================${nc}"
echo ""
echo -e "${blue}What do you want to do?${nc}"
echo -e "  ${white}1${nc} 🔒 Lock a user account"
echo -e "  ${white}2${nc} 🔓 Unlock a user account"
echo -e "  ${white}3${nc} 📊 Check user status"
echo -e "  ${white}4${nc} 📋 List all users"
echo -e "  ${white}5${nc} 🚪 Exit"
echo ""
read -p "Select option [1-5]: " option

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
        clear
        display_available_users
        read -n 1 -s -r -p "Press any key to continue..."
        exec $0
        ;;
    5)
        echo -e "${green}👋 Goodbye!${nc}"
        exit 0
        ;;
    *)
        echo -e "${red}❌ Invalid option!${nc}"
        exit 1
        ;;
esac

clear
echo -e "${yellow}=========================================${nc}"
echo -e "${action_color}          USER ${action^^} TOOL           ${nc}"
echo -e "${yellow}=========================================${nc}"
echo ""

# Display available users
display_available_users

# Input username
read -p "Input USERNAME to $action: " username

# Validate input
if ! validate_username "$username"; then
    exit 1
fi

# Check if user exists
if ! id "$username" &>/dev/null; then
    echo -e "${red}❌ Error: Username '${username}' not found in your server.${nc}"
    display_available_users
    exit 1
fi

# Get current user info
user_id=$(id -u "$username")
user_home=$(eval echo ~$username 2>/dev/null || echo "unknown")
current_status=$(get_user_status "$username")

# Display user information
echo ""
echo -e "${blue}👤 User Information:${nc}"
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
            echo -e "${yellow}⚠️ User '${username}' is already locked.${nc}"
            echo ""
            read -p "Do you want to continue anyway? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${yellow}Operation cancelled.${nc}"
                log_activity "LOCK_ATTEMPT" "$username" "CANCELLED_ALREADY_LOCKED"
                exit 0
            fi
        fi

        # Confirm lock action
        echo -e "${red}🚨 WARNING: This will prevent user '${username}' from logging in!${nc}"
        echo -e "${red}    • All active connections will be terminated${nc}"
        echo -e "${red}    • Access via SSH and WebSocket will be blocked${nc}"
        echo -e "${red}    • User cannot login until unlocked${nc}"
        echo ""
        read -p "Are you sure you want to lock this user? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${yellow}Operation cancelled.${nc}"
            log_activity "LOCK_ATTEMPT" "$username" "CANCELLED"
            exit 0
        fi

        lock_user "$username"
        ;;

    "unlock")
        # Check if user is already unlocked
        if [[ "$current_status" == "unlocked" ]]; then
            echo -e "${yellow}⚠️ User '${username}' is already unlocked.${nc}"
            echo ""
            read -p "Do you want to continue anyway? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${yellow}Operation cancelled.${nc}"
                log_activity "UNLOCK_ATTEMPT" "$username" "CANCELLED_ALREADY_UNLOCKED"
                exit 0
            fi
        fi

        # Confirm unlock action
        echo -e "${green}✅ This will allow user '${username}' to login again.${nc}"
        echo -e "${green}    • SSH access will be restored${nc}"
        echo -e "${green}    • WebSocket access will be restored${nc}"
        echo -e "${green}    • User can login normally${nc}"
        echo ""
        read -p "Are you sure you want to unlock this user? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${yellow}Operation cancelled.${nc}"
            log_activity "UNLOCK_ATTEMPT" "$username" "CANCELLED"
            exit 0
        fi

        unlock_user "$username"
        ;;

    "status")
        show_detailed_status "$username"
        log_activity "STATUS_CHECK" "$username" "VIEWED"
        ;;
esac

echo ""
read -n 1 -s -r -p "Press any key to continue..."
m-sshovpn