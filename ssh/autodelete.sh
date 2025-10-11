#!/bin/bash
# =========================================
# AUTO DELETE EXPIRED USERS
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
echo -e "${blue}             AUTO DELETE             ${nc}"
echo -e "${red}=========================================${nc}"

# Function to delete expired users
delete_expired_users() {
    hariini=$(date +%d-%m-%Y)
    echo -e "${green}Processing expired users...${nc}"
    echo ""
    
    # Create temporary files
    cat /etc/shadow | cut -d: -f1,8 | sed /:$/d > /tmp/expirelist.txt
    totalaccounts=$(cat /tmp/expirelist.txt | wc -l)
    
    # Initialize counters
    deleted_count=0
    active_count=0
    
    echo -e "${yellow}Checking $totalaccounts user accounts...${nc}"
    echo -e "${blue}=========================================${nc}"
    
    for((i=1; i<=$totalaccounts; i++))
    do
        tuserval=$(head -n $i /tmp/expirelist.txt | tail -n 1)
        username=$(echo $tuserval | cut -f1 -d:)
        userexp=$(echo $tuserval | cut -f2 -d:)
        
        # Skip if no expiration date
        if [ -z "$userexp" ]; then
            continue
        fi
        
        userexpireinseconds=$(( $userexp * 86400 ))
        tglexp=$(date -d @$userexpireinseconds)             
        tgl=$(echo $tglexp | awk -F" " '{print $3}')
        
        while [ ${#tgl} -lt 2 ]
        do
            tgl="0"$tgl
        done
        
        while [ ${#username} -lt 15 ]
        do
            username=$username" " 
        done
        
        bulantahun=$(echo $tglexp | awk -F" " '{print $2,$6}')
        todaystime=$(date +%s)
        
        if [ $userexpireinseconds -ge $todaystime ]; then
            # User is still active
            active_count=$((active_count + 1))
            echo -e "${green}✓ Active  : $username - Expires: $tgl $bulantahun${nc}"
        else
            # User is expired - delete
            deleted_count=$((deleted_count + 1))
            echo -e "${red}✗ Deleted : $username - Expired: $tgl $bulantahun${nc}"
            
            # Log the deletion
            echo "Expired- Username : $username expired at: $tgl $bulantahun and removed: $hariini" >> /usr/local/bin/deleteduser
            
            # Delete the user
            userdel $username 2>/dev/null
            
            # Also remove from other files if they exist
            sed -i "/^### $username ###/d" /etc/xray/config.json 2>/dev/null
            sed -i "/^### $username ###/d" /etc/xray/ssh.txt 2>/dev/null
        fi
    done
    
    # Clean up
    rm -f /tmp/expirelist.txt
    
    echo -e "${blue}=========================================${nc}"
    echo -e "${green}PROCESS COMPLETED${nc}"
    echo -e "${white}Total Accounts Checked : $totalaccounts${nc}"
    echo -e "${green}Active Accounts        : $active_count${nc}"
    echo -e "${red}Deleted Accounts       : $deleted_count${nc}"
    echo -e "${blue}=========================================${nc}"
}

# Function to show deletion log
show_deletion_log() {
    if [ -f "/usr/local/bin/deleteduser" ]; then
        echo -e "${yellow}LAST DELETION HISTORY:${nc}"
        echo -e "${blue}=========================================${nc}"
        tail -10 /usr/local/bin/deleteduser
        echo -e "${blue}=========================================${nc}"
    else
        echo -e "${yellow}No deletion history found${nc}"
    fi
}

# Main execution
delete_expired_users
echo ""
show_deletion_log

echo ""
echo -e "${red}=========================================${nc}"
echo -e "${green}              MENU OPTIONS              ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1 Run Auto Delete Again${nc}"
echo -e "${white}2 View Full Deletion Log${nc}"
echo -e "${white}3 Clear Deletion History${nc}"
echo -e "${white}4 Back to SSH Menu${nc}"
echo -e "${white}5 Exit${nc}"
echo -e "${red}=========================================${nc}"
echo ""

read -p "Select option [1-5]: " option

case $option in
    1)
        echo -e "${green}Running auto delete again...${nc}"
        sleep 1
        exec $0
        ;;
    2)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}          FULL DELETION LOG           ${nc}"
        echo -e "${red}=========================================${nc}"
        if [ -f "/usr/local/bin/deleteduser" ]; then
            cat /usr/local/bin/deleteduser
        else
            echo -e "${yellow}No deletion history found${nc}"
        fi
        echo -e "${red}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        exec $0
        ;;
    3)
        if [ -f "/usr/local/bin/deleteduser" ]; then
            rm -f /usr/local/bin/deleteduser
            echo -e "${green}Deletion history cleared successfully!${nc}"
        else
            echo -e "${yellow}No deletion history to clear${nc}"
        fi
        sleep 2
        exec $0
        ;;
    4)
        echo -e "${green}Returning to SSH Menu...${nc}"
        sleep 1
        m-sshovpn
        ;;
    5)
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
