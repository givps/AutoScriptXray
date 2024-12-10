#!/bin/bash
# Quick Setup | Script Setup Manager
# Edition : Stable Edition 1.0
# Author  : givps
# The MIT License (MIT)
# (C) Copyright 2023
# =========================================
# pewarna hidup
BRed='\e[1;31m'
BGreen='\e[1;32m'
BYellow='\e[1;33m'
BBlue='\e[1;34m'
BPurple='\e[1;35m'
NC='\e[0m'
MYIP=$(wget -qO- ipv4.icanhazip.com);
echo "Checking VPS"
clear
if [ ! -e /usr/local/bin/reboot_otomatis ]; then
echo '#!/bin/bash' > /usr/local/bin/reboot_otomatis 
echo 'tanggal=$(date +"%m-%d-%Y")' >> /usr/local/bin/reboot_otomatis 
echo 'waktu=$(date +"%T")' >> /usr/local/bin/reboot_otomatis 
echo 'echo "Server successfully rebooted on the date of $tanggal hit $waktu." >> /root/log-reboot.txt' >> /usr/local/bin/reboot_otomatis 
echo '/sbin/shutdown -r now' >> /usr/local/bin/reboot_otomatis 
chmod +x /usr/local/bin/reboot_otomatis
fi
clear
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;34m                 AUTO-REBOOT MENU                 \e[0m"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e ""
echo -e "\e[1;35m 1 \e[0m Set Auto-Reboot Every 1 Hour"
echo -e "\e[1;35m 2 \e[0m Set Auto-Reboot Every 6 Hours"
echo -e "\e[1;35m 3 \e[0m Set Auto-Reboot Every 12 Hours"
echo -e "\e[1;35m 4 \e[0m Set Auto-Reboot Every 1 Day"
echo -e "\e[1;35m 5 \e[0m Set Auto-Reboot Every 1 Week"
echo -e "\e[1;35m 6 \e[0m Set Auto-Reboot Every 1 Month"
echo -e "\e[1;35m 7 \e[0m Turn off Auto-Reboot"
echo -e "\e[1;35m 8 \e[0m View reboot log"
echo -e "\e[1;35m 9 \e[0m Remove reboot log"
echo -e ""
echo -e "\e[1;35m 0 \e[0m Back To Menu"
echo -e ""
echo -e "\e[1;34m Press x or [ Ctrl+C ] To-Exit \e[0m"
echo -e ""
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e ""
read -p " Select menu : " x
if test $x -eq 1; then
echo "10 * * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
echo "Auto-Reboot has been set every an hour."
elif test $x -eq 2; then
echo "10 */6 * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
echo "Auto-Reboot has been successfully set every 6 hours."
elif test $x -eq 3; then
echo "10 */12 * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
echo "Auto-Reboot has been successfully set every 12 hours."
elif test $x -eq 4; then
echo "10 0 * * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
echo "Auto-Reboot has been successfully set once a day."
elif test $x -eq 5; then
echo "10 0 */7 * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
echo "Auto-Reboot has been successfully set once a week."
elif test $x -eq 6; then
echo "10 0 1 * * root /usr/local/bin/reboot_otomatis" > /etc/cron.d/reboot_otomatis
echo "Auto-Reboot has been successfully set once a month."
elif test $x -eq 7; then
rm -f /etc/cron.d/reboot_otomatis
echo "Auto-Reboot successfully TURNED OFF."
elif test $x -eq 8; then
if [ ! -e /root/log-reboot.txt ]; then
	clear
    echo -e "\e[1;33m -------------------------------------------------\e[0m"
    echo -e "\e[1;34m                  AUTO-REBOOT LOG                 \e[0m"
    echo -e "\e[1;33m -------------------------------------------------\e[0m"
    echo -e ""
    echo " No reboot activity found \e[0m"
    echo -e ""
    echo -e "\e[1;33m -------------------------------------------------\e[0m"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    auto-reboot
	else
	clear
    echo -e "\e[1;33m -------------------------------------------------\e[0m"
    echo -e "\e[1;34m                   AUTO-REBOOT LOG         	   \e[0m"
    echo -e "\e[1;33m -------------------------------------------------\e[0m"
    echo -e ""    
	echo ' LOG REBOOT \e[0m'
	cat /root/log-reboot.txt
    echo -e ""
    echo -e "\e[1;33m -------------------------------------------------\e[0m"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    auto-reboot    
fi
elif test $x -eq 9; then
clear
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e "\e[1;34m                  AUTO-REBOOT LOG                 \e[0m"
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo -e ""  
echo "" > /root/log-reboot.txt
echo " Auto Reboot Log successfully deleted! \e[0m"
echo -e ""
echo -e "\e[1;33m -------------------------------------------------\e[0m"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
auto-reboot 
elif test $x -eq 0; then
clear
m-system
else
clear
echo ""
echo "Options Not Found In Menu"
echo ""
read -n 1 -s -r -p "Press any key to back on menu"
auto-reboot 
fi
