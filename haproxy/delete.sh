#!/bin/bash
# =========================================
# DELETE SSH USER - HAPROXY WEBSOCKET VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# Function to delete user
delete_user() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}             DELETE USER               ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Show current SSH users (shell /bin/false untuk HAProxy WS users)
    echo -e "${yellow}Current SSH Users:${nc}"
    echo -e "${blue}=========================================${nc}"
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read user; do
        if [ "$user" != "sync" ] && [ "$user" != "halt" ]; then
            exp_date=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            echo -e "${white}• $user${nc} ${yellow}(Expires: $exp_date)${nc}"
        fi
    done
    echo -e "${blue}=========================================${nc}"
    echo ""
    
    read -p "Username SSH to Delete : " Pengguna
    
    if [ -z "$Pengguna" ]; then
        echo -e "${red}Error: Username cannot be empty!${nc}"
        return 1
    fi
    
    if getent passwd $Pengguna > /dev/null 2>&1; then
        # Get user info before deletion
        user_shell=$(getent passwd $Pengguna | cut -d: -f7)
        user_expiry=$(chage -l $Pengguna 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        
        # Confirm deletion
        echo ""
        echo -e "${yellow}User Information:${nc}"
        echo -e "  Username : $Pengguna"
        echo -e "  Shell    : $user_shell"
        echo -e "  Expiry   : $user_expiry"
        echo ""
        echo -e "${red}⚠️  ARE YOU SURE YOU WANT TO DELETE THIS USER?${nc}"
        read -p "Confirm deletion? [y/N]: " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo -e "${yellow}Deleting user $Pengguna...${nc}"
            
            # Kill all user processes
            echo -e "${yellow}Stopping user processes...${nc}"
            pkill -9 -u $Pengguna 2>/dev/null
            sleep 2
            
            # Force kill any remaining processes
            ps -u $Pengguna 2>/dev/null | awk '{print $1}' | grep -v PID | while read pid; do
                kill -9 $pid 2>/dev/null
            done
            
            # Remove user from HAProxy stats if exists
            if [ -f "/etc/haproxy/haproxy.cfg" ]; then
                echo -e "${yellow}Cleaning HAProxy configuration...${nc}"
                # Remove user-specific ACLs if any
                sed -i "/### $Pengguna ###/,/### END $Pengguna ###/d" /etc/haproxy/haproxy.cfg 2>/dev/null
            fi
            
            # Delete user and home directory
            echo -e "${yellow}Removing user account...${nc}"
            userdel -r $Pengguna > /dev/null 2>&1
            
            # Remove from SSH allowed users file if exists
            if [ -f "/etc/ssh/allowed_users" ]; then
                sed -i "/^$Pengguna$/d" /etc/ssh/allowed_users 2>/dev/null
            fi
            
            # Remove from custom user lists
            if [ -f "/etc/xray/ssh.txt" ]; then
                sed -i "/^$Pengguna:/d" /etc/xray/ssh.txt 2>/dev/null
            fi
            
            # Clean up WebSocket proxy logs if any
            if [ -f "/var/log/ws-proxy.log" ]; then
                sed -i "/$Pengguna/d" /var/log/ws-proxy.log 2>/dev/null
            fi
            
            # Restart services to clean up connections
            echo -e "${yellow}Restarting services...${nc}"
            systemctl restart ssh haproxy ws-proxy 2>/dev/null
            
            echo -e "${green}✅ SUCCESS: User $Pengguna was completely removed.${nc}"
            
            # Log the deletion
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Deleted user: $Pengguna (Shell: $user_shell, Expiry: $user_expiry)" >> /var/log/user-deletion.log
            
            # Show remaining users count
            remaining_users=$(getent passwd | grep -E ":/bin/false$" | grep -v -E "^(sync|halt)" | wc -l)
            echo -e "${blue}Remaining SSH users: $remaining_users${nc}"
            
        else
            echo -e "${yellow}Deletion cancelled.${nc}"
        fi
    else
        echo -e "${red}❌ ERROR: User $Pengguna does not exist.${nc}"
        echo -e "${yellow}Available users:${nc}"
        getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | grep -v -E "^(sync|halt)" | head -10
    fi
}

# Function to show deletion log
show_deletion_log() {
    if [ -f "/var/log/user-deletion.log" ]; then
        echo ""
        echo -e "${yellow}Recent Deletion History:${nc}"
        echo -e "${blue}=========================================${nc}"
        tail -10 /var/log/user-deletion.log | while read line; do
            echo -e "${white}$line${nc}"
        done
        echo -e "${blue}=========================================${nc}"
    else
        echo -e "${yellow}No deletion history found${nc}"
    fi
}

# Function to show current user stats
show_user_stats() {
    echo ""
    echo -e "${yellow}📊 Current User Statistics:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    total_users=$(getent passwd | grep -E ":/bin/false$" | grep -v -E "^(sync|halt)" | wc -l)
    active_users=$(who | cut -d' ' -f1 | sort -u | wc -l)
    
    echo -e "Total SSH Users  : ${green}$total_users${nc}"
    echo -e "Currently Active : ${yellow}$active_users${nc}"
    
    # Show users expiring soon (within 3 days)
    echo -e "\n${yellow}Users expiring in next 3 days:${nc}"
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | grep -v -E "^(sync|halt)" | while read user; do
        expiry=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        if [ "$expiry" != "never" ]; then
            expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
            today_sec=$(date +%s)
            days_left=$(( (expiry_sec - today_sec) / 86400 ))
            if [ $days_left -le 3 ] && [ $days_left -ge 0 ]; then
                echo -e "  ${red}$user${nc} - ${yellow}$days_left day(s) left${nc}"
            fi
        fi
    done
    echo -e "${blue}=========================================${nc}"
}

# Function to bulk delete expired users
bulk_delete_expired() {
    echo ""
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         BULK DELETE EXPIRED USERS     ${nc}"
    echo -e "${red}=========================================${nc}"
    
    expired_count=0
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | grep -v -E "^(sync|halt)" | while read user; do
        expiry=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        if [ "$expiry" != "never" ]; then
            expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
            today_sec=$(date +%s)
            if [ $expiry_sec -lt $today_sec ]; then
                echo -e "${yellow}Deleting expired user: $user${nc}"
                pkill -9 -u $user 2>/dev/null
                userdel -r $user > /dev/null 2>&1
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Auto-deleted expired user: $user" >> /var/log/user-deletion.log
                ((expired_count++))
            fi
        fi
    done
    
    if [ $expired_count -gt 0 ]; then
        echo -e "${green}✅ Deleted $expired_count expired users${nc}"
        systemctl restart ssh haproxy ws-proxy 2>/dev/null
    else
        echo -e "${yellow}No expired users found${nc}"
    fi
}

# Main function
main() {
    delete_user
    show_user_stats
    show_deletion_log
    
    echo ""
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}              MENU OPTIONS             ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${white}1${nc} Delete Another User"
    echo -e "${white}2${nc} View Full Deletion Log"
    echo -e "${white}3${nc} Clear Deletion Log"
    echo -e "${white}4${nc} Bulk Delete Expired Users"
    echo -e "${white}5${nc} Show User Statistics"
    echo -e "${white}6${nc} Back to SSH Menu"
    echo -e "${white}7${nc} Exit"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    read -p "Select option [1-7]: " option
    
    case $option in
        1)
            # Delete another user
            exec $0
            ;;
        2)
            # View full deletion log
            clear
            echo -e "${red}=========================================${nc}"
            echo -e "${blue}          FULL DELETION LOG           ${nc}"
            echo -e "${red}=========================================${nc}"
            if [ -f "/var/log/user-deletion.log" ]; then
                cat /var/log/user-deletion.log
            else
                echo -e "${yellow}No deletion history found${nc}"
            fi
            echo -e "${red}=========================================${nc}"
            echo ""
            read -n 1 -s -r -p "Press any key to continue..."
            exec $0
            ;;
        3)
            # Clear deletion log
            if [ -f "/var/log/user-deletion.log" ]; then
                rm -f /var/log/user-deletion.log
                echo -e "${green}Deletion log cleared successfully!${nc}"
            else
                echo -e "${yellow}No deletion log to clear${nc}"
            fi
            sleep 2
            exec $0
            ;;
        4)
            # Bulk delete expired users
            bulk_delete_expired
            read -n 1 -s -r -p "Press any key to continue..."
            exec $0
            ;;
        5)
            # Show user statistics
            clear
            show_user_stats
            read -n 1 -s -r -p "Press any key to continue..."
            exec $0
            ;;
        6)
            # Back to SSH menu
            echo -e "${green}Returning to SSH Menu...${nc}"
            sleep 1
            m-sshovpn
            ;;
        7)
            # Exit
            echo -e "${green}Exiting...${nc}"
            sleep 1
            clear
            exit 0
            ;;
        *)
            echo -e "${red}Invalid option! Returning to SSH Menu...${nc}"
            sleep 2
            m-sshovpn
            ;;
    esac
}

# Create log file if not exists
touch /var/log/user-deletion.log

# Start the script
main