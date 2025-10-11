#!/bin/bash
# =========================================
# Auto-Reboot Menu
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

# ==========================================
# Getting system info
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# Function to create reboot script
create_reboot_script() {
    if [ ! -e /usr/local/bin/reboot_otomatis ]; then
        cat > /usr/local/bin/reboot_otomatis << EOF
#!/bin/bash
tanggal=\$(date +"%m-%d-%Y")
waktu=\$(date +"%T")
echo "Server successfully rebooted on \$tanggal at \$waktu." >> /root/log-reboot.txt
/sbin/shutdown -r now
EOF
        chmod +x /usr/local/bin/reboot_otomatis
        echo -e "${green}Reboot script created successfully${nc}"
    fi
}

# Function to display current reboot schedule
show_current_schedule() {
    if [ -e /etc/cron.d/reboot_otomatis ]; then
        current_cron=$(cat /etc/cron.d/reboot_otomatis)
        echo -e "${yellow}Current Schedule:${nc}"
        echo -e "  ${green}$current_cron${nc}"
    else
        echo -e "${red}Auto-Reboot is currently OFF${nc}"
    fi
}

# Function to display reboot log
show_reboot_log() {
    if [ ! -e /root/log-reboot.txt ]; then
        echo -e "${yellow}No reboot activity found${nc}"
    else
        echo -e "${green}Reboot Log:${nc}"
        echo -e "${blue}=========================================${nc}"
        cat /root/log-reboot.txt
        echo -e "${blue}=========================================${nc}"
        total_reboots=$(wc -l < /root/log-reboot.txt)
        echo -e "${yellow}Total reboots: $total_reboots${nc}"
    fi
}

# Main menu
clear
create_reboot_script

echo -e "${red}=========================================${nc}"
echo -e "${blue}            AUTO-REBOOT MENU            ${nc}"
echo -e "${red}=========================================${nc}"
echo ""

# Show current status
show_current_schedule
echo ""

echo -e "${white} 1 ${nc} Set Auto-Reboot Every 1 Hour"
echo -e "${white} 2 ${nc} Set Auto-Reboot Every 6 Hours" 
echo -e "${white} 3 ${nc} Set Auto-Reboot Every 12 Hours"
echo -e "${white} 4 ${nc} Set Auto-Reboot Every 1 Day"
echo -e "${white} 5 ${nc} Set Auto-Reboot Every 1 Week"
echo -e "${white} 6 ${nc} Set Auto-Reboot Every 1 Month"
echo -e "${white} 7 ${nc} Turn off Auto-Reboot"
echo -e "${white} 8 ${nc} View reboot log"
echo -e "${white} 9 ${nc} Remove reboot log"
echo -e "${white}10 ${nc} Test reboot script (Dry run)"
echo ""
echo -e "${white} 0 ${nc} Back To Menu"
echo ""
echo -e "${blue} Press x or [ Ctrl+C ] To-Exit ${nc}"
echo ""
echo -e "${red}=========================================${nc}"
echo ""
read -p " Select menu : " x

case $x in
    1)
        echo "10 * * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
        echo -e "${green}Auto-Reboot has been set every hour${nc}"
        ;;
    2)
        echo "10 */6 * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
        echo -e "${green}Auto-Reboot has been set every 6 hours${nc}"
        ;;
    3)
        echo "10 */12 * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
        echo -e "${green}Auto-Reboot has been set every 12 hours${nc}"
        ;;
    4)
        echo "10 0 * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
        echo -e "${green}Auto-Reboot has been set once a day${nc}"
        ;;
    5)
        echo "10 0 */7 * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
        echo -e "${green}Auto-Reboot has been set once a week${nc}"
        ;;
    6)
        echo "10 0 1 * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
        echo -e "${green}Auto-Reboot has been set once a month${nc}"
        ;;
    7)
        if [ -e /etc/cron.d/reboot_otomatis ]; then
            rm -f /etc/cron.d/reboot_otomatis
            echo -e "${green}Auto-Reboot successfully TURNED OFF${nc}"
        else
            echo -e "${yellow}Auto-Reboot is already OFF${nc}"
        fi
        ;;
    8)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}             AUTO-REBOOT LOG            ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        show_reboot_log
        echo ""
        echo -e "${red}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        auto-reboot
        ;;
    9)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}            AUTO-REBOOT LOG             ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""  
        if [ -e /root/log-reboot.txt ]; then
            echo "" > /root/log-reboot.txt
            echo -e "${green}Auto Reboot Log successfully deleted!${nc}"
        else
            echo -e "${yellow}No reboot log found${nc}"
        fi
        echo ""
        echo -e "${red}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        auto-reboot 
        ;;
    10)
        # Test reboot script (dry run)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}           TEST REBOOT SCRIPT           ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${yellow}Testing reboot script (dry run)...${nc}"
        echo -e "${green}Script would execute: /usr/local/bin/reboot_otomatis${nc}"
        echo -e "${yellow}But no actual reboot will occur${nc}"
        echo ""
        echo -e "${red}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        auto-reboot
        ;;
    0)
        clear
        m-system
        ;;
    [xX])
        echo ""
        echo -e "${yellow}Exiting...${nc}"
        exit 0
        ;;
    *)
        clear
        echo ""
        echo -e "${red}Options Not Found In Menu${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        auto-reboot 
        ;;
esac

# Show updated status
echo ""
show_current_schedule
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
auto-reboot
