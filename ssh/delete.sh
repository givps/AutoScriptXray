#!/bin/bash
# =========================================
# DELETE SSH USER
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
    echo -e "${blue}             DELETE USER                 ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Show current users
    echo -e "${yellow}Current SSH Users:${nc}"
    echo -e "${blue}=========================================${nc}"
    getent passwd | grep -E "/home/.*:/bin/bash" | cut -d: -f1 | while read user; do
        echo -e "${white}• $user${nc}"
    done
    echo -e "${blue}=========================================${nc}"
    echo ""
    
    read -p "Username SSH to Delete : " Pengguna
    
    if [ -z "$Pengguna" ]; then
        echo -e "${red}Error: Username cannot be empty!${nc}"
        return 1
    fi
    
    if getent passwd $Pengguna > /dev/null 2>&1; then
        # Confirm deletion
        echo ""
        echo -e "${yellow}Are you sure you want to delete user: $Pengguna?${nc}"
        read -p "Confirm deletion? [y/N]: " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            # Kill user processes
            pkill -u $Pengguna 2>/dev/null
            
            # Delete user and home directory
            userdel -r $Pengguna > /dev/null 2>&1
            
            # Remove from additional files if they exist
            if [ -f "/etc/xray/config.json" ]; then
                sed -i "/### $Pengguna ###/d" /etc/xray/config.json 2>/dev/null
            fi
            
            if [ -f "/etc/xray/ssh.txt" ]; then
                sed -i "/^$Pengguna:/d" /etc/xray/ssh.txt 2>/dev/null
            fi
            
            echo -e "${green}✓ Success: User $Pengguna was removed.${nc}"
            
            # Log the deletion
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Deleted user: $Pengguna" >> /var/log/user-deletion.log
        else
            echo -e "${yellow}Deletion cancelled.${nc}"
        fi
    else
        echo -e "${red}✗ Error: User $Pengguna does not exist.${nc}"
    fi
}

# Function to show deletion log
show_deletion_log() {
    if [ -f "/var/log/user-deletion.log" ]; then
        echo ""
        echo -e "${yellow}Recent Deletion History:${nc}"
        echo -e "${blue}=========================================${nc}"
        tail -5 /var/log/user-deletion.log
        echo -e "${blue}=========================================${nc}"
    fi
}

# Main function
main() {
    delete_user
    show_deletion_log
    
    echo ""
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}              MENU OPTIONS              ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${white}1${nc} Delete Another User"
    echo -e "${white}2${nc} View Full Deletion Log"
    echo -e "${white}3${nc} Clear Deletion Log"
    echo -e "${white}4${nc} Back to SSH Menu"
    echo -e "${white}5${nc} Exit"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    read -p "Select option [1-5]: " option
    
    case $option in
        1)
            # Delete another user
            exec $0
            ;;
        2)
            # View full deletion log
            clear
            echo -e "${red}=========================================${nc}"
            echo -e "${blue}          FULL DELETION LOG            ${nc}"
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
            # Back to SSH menu
            echo -e "${green}Returning to SSH Menu...${nc}"
            sleep 1
            m-sshovpn
            ;;
        5)
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

# Start the script
main
