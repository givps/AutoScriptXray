#!/bin/bash
# =========================================
# WEBMIN MENU
# =========================================

# ---------- Colors ----------
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# ---------- Status Variables ----------
Green_font_prefix="\033[32m" 
Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[Installed]${Font_color_suffix}"
Error="${Red_font_prefix}[Not Installed]${Font_color_suffix}"

# Function to check Webmin status
check_webmin_status() {
    local cek=$(netstat -ntlp | grep 10000 | awk '{print $7}' | cut -d'/' -f2 2>/dev/null)
    if [[ "$cek" = "perl" ]]; then
        echo "$Info"
    else
        echo "$Error"
    fi
}

# Function to get server IP
get_server_ip() {
    wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me
}

# Function to install Webmin
install_webmin() {
    local IP=$(get_server_ip)
    
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}           INSTALL WEBMIN            ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    echo -e "[${green}INFO${nc}] Adding Webmin Repository..."
    sh -c 'echo "deb http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list'
    
    # Install dependencies
    apt install gnupg gnupg1 gnupg2 -y > /dev/null 2>&1
    
    # Add Webmin key
    echo -e "[${green}INFO${nc}] Adding Webmin GPG Key..."
    wget -q http://www.webmin.com/jcameron-key.asc > /dev/null 2>&1
    apt-key add jcameron-key.asc > /dev/null 2>&1
    
    # Update and install
    echo -e "[${green}INFO${nc}] Installing Webmin..."
    apt update > /dev/null 2>&1
    apt install webmin -y > /dev/null 2>&1
    
    # Disable SSL for easier access
    echo -e "[${green}INFO${nc}] Configuring Webmin..."
    sed -i 's/ssl=1/ssl=0/g' /etc/webmin/miniserv.conf
    
    # Restart service
    echo -e "[${green}INFO${nc}] Starting Webmin Service..."
    systemctl enable webmin > /dev/null 2>&1
    systemctl restart webmin > /dev/null 2>&1
    
    # Cleanup
    rm -f /root/jcameron-key.asc > /dev/null 2>&1
    
    echo ""
    echo -e "[${green}SUCCESS${nc}] Webmin Installed Successfully!"
    echo ""
    echo -e "${cyan}Access Webmin at:${nc}"
    echo -e "  ${yellow}http://$IP:10000${nc}"
    echo -e "  ${yellow}http://$(hostname):10000${nc}"
    echo ""
    echo -e "${yellow}Default login:${nc}"
    echo -e "  Username: ${white}root${nc}"
    echo -e "  Password: ${white}Your server root password${nc}"
    echo ""
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-webmin
}

# Function to restart Webmin
restart_webmin() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}          RESTART WEBMIN             ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    echo -e "[${green}INFO${nc}] Restarting Webmin Service..."
    systemctl restart webmin > /dev/null 2>&1
    
    # Check if restart was successful
    sleep 2
    if systemctl is-active --quiet webmin; then
        echo -e "[${green}SUCCESS${nc}] Webmin Restarted Successfully!"
    else
        echo -e "[${red}ERROR${nc}] Failed to restart Webmin!"
    fi
    
    echo ""
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-webmin
}

# Function to uninstall Webmin
uninstall_webmin() {
    clear
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}          UNINSTALL WEBMIN            ${nc}"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    # Confirmation
    echo -e "${yellow}WARNING: This will completely remove Webmin from your system.${nc}"
    read -p "Are you sure you want to continue? [y/N]: " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "[${yellow}INFO${nc}] Uninstall cancelled."
        sleep 2
        m-webmin
        return
    fi
    
    echo -e "[${green}INFO${nc}] Removing Webmin Repository..."
    rm -f /etc/apt/sources.list.d/webmin.list
    
    echo -e "[${green}INFO${nc}] Removing Webmin..."
    apt update > /dev/null 2>&1
    apt autoremove --purge webmin -y > /dev/null 2>&1
    
    # Remove any leftover files
    rm -rf /etc/webmin /usr/share/webmin > /dev/null 2>&1
    
    echo -e "[${green}SUCCESS${nc}] Webmin Uninstalled Successfully!"
    echo ""
    echo -e "${red}=========================================${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to back on menu"
    m-webmin
}

# Function to show Webmin info
show_webmin_info() {
    if systemctl is-active --quiet webmin; then
        local IP=$(get_server_ip)
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}          WEBMIN INFORMATION          ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        echo -e "${cyan}Access URLs:${nc}"
        echo -e "  ${yellow}http://$IP:10000${nc}"
        echo -e "  ${yellow}http://$(hostname):10000${nc}"
        echo ""
        echo -e "${cyan}Login Credentials:${nc}"
        echo -e "  Username: ${white}root${nc}"
        echo -e "  Password: ${white}Your server root password${nc}"
        echo ""
        echo -e "${cyan}Service Status:${nc}"
        systemctl status webmin --no-pager -l | head -10
        echo ""
        echo -e "${red}=========================================${nc}"
        echo ""
        read -n 1 -s -r -p "Press any key to back on menu"
        m-webmin
    else
        echo -e "[${red}ERROR${nc}] Webmin is not running!"
        sleep 2
        m-webmin
    fi
}

# Main menu
clear
webmin_status=$(check_webmin_status)

echo -e "${red}=========================================${nc}"
echo -e "${blue}            WEBMIN MENU               ${nc}"
echo -e "${red}=========================================${nc}"
echo ""
echo -e " Status: $webmin_status"
echo ""
echo -e " ${cyan}1${nc} Install Webmin"
echo -e " ${cyan}2${nc} Restart Webmin"
echo -e " ${cyan}3${nc} Uninstall Webmin"
echo -e " ${cyan}4${nc} Webmin Information"
echo ""
echo -e " ${red}0${nc} Back To Main Menu"
echo ""
echo -e " Press ${yellow}x${nc} or [Ctrl+C] to Exit"
echo ""
echo -e "${red}=========================================${nc}"
echo ""
read -rp " Please select an option [0-4]: " num

case $num in
    1)
        install_webmin
        ;;
    2)
        if [[ "$webmin_status" == "$Info" ]]; then
            restart_webmin
        else
            echo -e "[${red}ERROR${nc}] Webmin is not installed!"
            sleep 2
            m-webmin
        fi
        ;;
    3)
        if [[ "$webmin_status" == "$Info" ]]; then
            uninstall_webmin
        else
            echo -e "[${red}ERROR${nc}] Webmin is not installed!"
            sleep 2
            m-webmin
        fi
        ;;
    4)
        if [[ "$webmin_status" == "$Info" ]]; then
            show_webmin_info
        else
            echo -e "[${red}ERROR${nc}] Webmin is not installed!"
            sleep 2
            m-webmin
        fi
        ;;
    0)
        clear
        menu
        ;;
    x|X)
        exit 0
        ;;
    *)
        echo -e "[${red}ERROR${nc}] Invalid option!"
        sleep 2
        m-webmin
        ;;
esac
