#!/bin/bash
# =========================================
# AUTO DELETE EXPIRED USERS - HAPROXY WEBSOCKET VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}        AUTO DELETE - HAProxy WS       ${nc}"
echo -e "${red}=========================================${nc}"

# Configuration
DELETION_LOG="/var/log/auto-delete.log"
BACKUP_DIR="/root/user-backups"

# Function to delete expired users
delete_expired_users() {
    hariini=$(date +%d-%m-%Y)
    echo -e "${green}🔍 Processing expired users...${nc}"
    echo ""
    
    # Create temporary files - only for SSH users with /bin/false shell
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 > /tmp/ssh_users.txt
    totalaccounts=$(cat /tmp/ssh_users.txt | wc -l)
    
    # Initialize counters
    deleted_count=0
    active_count=0
    skipped_count=0
    
    echo -e "${yellow}📊 Checking $totalaccounts SSH user accounts...${nc}"
    echo -e "${blue}=========================================${nc}"
    
    # Create backup directory
    mkdir -p $BACKUP_DIR
    
    while read username; do
        if [ -z "$username" ] || [ "$username" = "sync" ] || [ "$username" = "halt" ]; then
            continue
        fi
        
        # Get user expiry info
        expiry_info=$(chage -l "$username" 2>/dev/null | grep "Account expires")
        userexp=$(echo "$expiry_info" | awk -F": " '{print $2}')
        
        # Skip if no expiration date or never expires
        if [ -z "$userexp" ] || [ "$userexp" = "never" ]; then
            skipped_count=$((skipped_count + 1))
            echo -e "${cyan}⏩ Skipped : $username - No expiry date${nc}"
            continue
        fi
        
        # Convert expiry date to seconds
        if [ "$userexp" != "never" ]; then
            userexpireinseconds=$(date -d "$userexp" +%s 2>/dev/null)
            if [ $? -ne 0 ]; then
                skipped_count=$((skipped_count + 1))
                echo -e "${yellow}⚠️  Error   : $username - Invalid expiry date: $userexp${nc}"
                continue
            fi
        else
            userexpireinseconds=9999999999
        fi
        
        todaystime=$(date +%s)
        days_left=$(( (userexpireinseconds - todaystime) / 86400 ))
        
        # Format username for display
        display_username=$(printf "%-15s" "$username")
        
        if [ $userexpireinseconds -ge $todaystime ]; then
            # User is still active
            active_count=$((active_count + 1))
            if [ $days_left -le 3 ]; then
                echo -e "${yellow}⚠️  Warning : $display_username - $days_left day(s) left${nc}"
            else
                echo -e "${green}✅ Active  : $display_username - $days_left day(s) left${nc}"
            fi
        else
            # User is expired - delete
            deleted_count=$((deleted_count + 1))
            echo -e "${red}🗑️  Deleted : $display_username - EXPIRED${nc}"
            
            # Create user info backup before deletion
            user_info=$(getent passwd "$username")
            user_home=$(echo "$user_info" | cut -d: -f6)
            user_shell=$(echo "$user_info" | cut -d: -f7)
            
            # Backup user info
            echo "Username: $username" > "$BACKUP_DIR/$username-backup-$hariini.txt"
            echo "Home: $user_home" >> "$BACKUP_DIR/$username-backup-$hariini.txt"
            echo "Shell: $user_shell" >> "$BACKUP_DIR/$username-backup-$hariini.txt"
            echo "Expired: $userexp" >> "$BACKUP_DIR/$username-backup-$hariini.txt"
            echo "Deleted: $(date)" >> "$BACKUP_DIR/$username-backup-$hariini.txt"
            
            # Kill all user processes
            echo -e "${yellow}  └─ Stopping processes...${nc}"
            pkill -9 -u "$username" 2>/dev/null
            sleep 2
            
            # Kill any remaining SSH/WebSocket sessions
            ps aux | grep "^$username" | grep -E "ssh|dropbear" | awk '{print $2}' | xargs kill -9 2>/dev/null
            
            # Delete the user and home directory
            echo -e "${yellow}  └─ Removing user account...${nc}"
            userdel -r "$username" 2>/dev/null
            
            # Clean up from HAProxy configuration if any user-specific rules
            if [ -f "/etc/haproxy/haproxy.cfg" ]; then
                sed -i "/### $username ###/,/### END $username ###/d" /etc/haproxy/haproxy.cfg 2>/dev/null
            fi
            
            # Clean up from other services
            if [ -f "/etc/ssh/allowed_users" ]; then
                sed -i "/^$username$/d" /etc/ssh/allowed_users 2>/dev/null
            fi
            
            if [ -f "/etc/xray/ssh.txt" ]; then
                sed -i "/^$username:/d" /etc/xray/ssh.txt 2>/dev/null
            fi
            
            # Log the deletion
            echo "$(date '+%Y-%m-%d %H:%M:%S') - DELETED: $username (Expired: $userexp, Home: $user_home)" >> "$DELETION_LOG"
            
            # Restart services to clean up connections
            systemctl restart ssh haproxy ws-proxy 2>/dev/null
        fi
    done < /tmp/ssh_users.txt
    
    # Clean up
    rm -f /tmp/ssh_users.txt
    
    echo -e "${blue}=========================================${nc}"
    echo -e "${green}🎯 PROCESS COMPLETED${nc}"
    echo -e "${white}Total Accounts Checked : $totalaccounts${nc}"
    echo -e "${green}Active Accounts        : $active_count${nc}"
    echo -e "${red}Deleted Accounts       : $deleted_count${nc}"
    echo -e "${cyan}Skipped Accounts       : $skipped_count${nc}"
    echo -e "${blue}=========================================${nc}"
}

# Function to show deletion log
show_deletion_log() {
    if [ -f "$DELETION_LOG" ]; then
        echo -e "${yellow}📜 LAST DELETION HISTORY:${nc}"
        echo -e "${blue}=========================================${nc}"
        tail -10 "$DELETION_LOG" | while read line; do
            echo -e "${white}$line${nc}"
        done
        echo -e "${blue}=========================================${nc}"
        
        total_deleted=$(wc -l < "$DELETION_LOG" 2>/dev/null || echo "0")
        echo -e "${yellow}Total deletions recorded: $total_deleted${nc}"
    else
        echo -e "${yellow}No deletion history found${nc}"
    fi
}

# Function to show backup files
show_backups() {
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
        echo -e "${yellow}💾 BACKUP FILES:${nc}"
        echo -e "${blue}=========================================${nc}"
        ls -la "$BACKUP_DIR"/*.txt 2>/dev/null | head -10 | while read file; do
            filename=$(basename "$file")
            size=$(du -h "$file" | cut -f1)
            echo -e "${white}$filename - $size${nc}"
        done
        echo -e "${blue}=========================================${nc}"
        
        backup_count=$(ls "$BACKUP_DIR"/*.txt 2>/dev/null | wc -l)
        echo -e "${yellow}Total backup files: $backup_count${nc}"
    else
        echo -e "${yellow}No backup files found${nc}"
    fi
}

# Function to show users expiring soon
show_expiring_soon() {
    echo -e "${yellow}⚠️  USERS EXPIRING SOON (3 days):${nc}"
    echo -e "${blue}=========================================${nc}"
    
    expiring_count=0
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read username; do
        if [ "$username" != "sync" ] && [ "$username" != "halt" ]; then
            expiry_info=$(chage -l "$username" 2>/dev/null | grep "Account expires")
            userexp=$(echo "$expiry_info" | awk -F": " '{print $2}')
            
            if [ "$userexp" != "never" ] && [ -n "$userexp" ]; then
                userexpireinseconds=$(date -d "$userexp" +%s 2>/dev/null)
                todaystime=$(date +%s)
                days_left=$(( (userexpireinseconds - todaystime) / 86400 ))
                
                if [ $days_left -le 3 ] && [ $days_left -ge 0 ]; then
                    echo -e "${red}• $username - $days_left day(s) left${nc}"
                    expiring_count=$((expiring_count + 1))
                fi
            fi
        fi
    done
    
    if [ $expiring_count -eq 0 ]; then
        echo -e "${green}No users expiring in 3 days${nc}"
    else
        echo -e "${blue}-----------------------------------------${nc}"
        echo -e "${red}Total users expiring soon: $expiring_count${nc}"
    fi
    echo -e "${blue}=========================================${nc}"
}

# Main execution
delete_expired_users
echo ""
show_expiring_soon
echo ""
show_deletion_log
echo ""
show_backups

echo ""
echo -e "${red}=========================================${nc}"
echo -e "${green}              MENU OPTIONS              ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Run Auto Delete Again"
echo -e "${white}2${nc} View Full Deletion Log"
echo -e "${white}3${nc} Clear Deletion History"
echo -e "${white}4${nc} Show Backup Files"
echo -e "${white}5${nc} Clean Old Backups (30+ days)"
echo -e "${white}6${nc} Back to SSH Menu"
echo -e "${white}7${nc} Exit"
echo -e "${red}=========================================${nc}"
echo ""

read -p "Select option [1-7]: " option

case $option in
    1)
        echo -e "${green}🔄 Running auto delete again...${nc}"
        sleep 1
        exec $0
        ;;
    2)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}          FULL DELETION LOG           ${nc}"
        echo -e "${red}=========================================${nc}"
        if [ -f "$DELETION_LOG" ]; then
            cat "$DELETION_LOG"
        else
            echo -e "${yellow}No deletion history found${nc}"
        fi
        echo -e "${red}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        exec $0
        ;;
    3)
        if [ -f "$DELETION_LOG" ]; then
            rm -f "$DELETION_LOG"
            echo -e "${green}✅ Deletion history cleared successfully!${nc}"
        else
            echo -e "${yellow}No deletion history to clear${nc}"
        fi
        sleep 2
        exec $0
        ;;
    4)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}            BACKUP FILES              ${nc}"
        echo -e "${red}=========================================${nc}"
        if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
            ls -la "$BACKUP_DIR"/
            echo -e "${red}=========================================${nc}"
            echo -e "${yellow}Total backup files: $(ls "$BACKUP_DIR"/*.txt 2>/dev/null | wc -l)${nc}"
        else
            echo -e "${yellow}No backup files found${nc}"
        fi
        echo -e "${red}=========================================${nc}"
        read -n 1 -s -r -p "Press any key to continue..."
        exec $0
        ;;
    5)
        echo -e "${yellow}🧹 Cleaning old backups (30+ days)...${nc}"
        find "$BACKUP_DIR" -name "*.txt" -mtime +30 -delete 2>/dev/null
        echo -e "${green}✅ Old backups cleaned!${nc}"
        sleep 2
        exec $0
        ;;
    6)
        echo -e "${green}↩️  Returning to SSH Menu...${nc}"
        sleep 1
        m-sshovpn
        ;;
    7)
        echo -e "${green}👋 Exiting...${nc}"
        sleep 1
        clear
        exit 0
        ;;
    *)
        echo -e "${red}❌ Invalid option! Returning to SSH Menu...${nc}"
        sleep 2
        m-sshovpn
        ;;
esac
