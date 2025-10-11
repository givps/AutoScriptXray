#!/bin/bash
# =========================================
# DNS Changer Menu
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
# ==========================================
# Getting system info
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# Function to get current DNS
get_current_dns() {
    if grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
        echo -e "${green}Current DNS:${nc}"
        grep "nameserver" /etc/resolv.conf
    else
        echo -e "${red}No DNS configured${nc}"
    fi
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to show popular DNS providers
show_dns_providers() {
    echo -e "${yellow}Popular DNS Providers:${nc}"
    echo -e "  ${cyan}•${nc} Google DNS: 8.8.8.8, 8.8.4.4"
    echo -e "  ${cyan}•${nc} Cloudflare: 1.1.1.1, 1.0.0.1"
    echo -e "  ${cyan}•${nc} Quad9: 9.9.9.9, 149.112.112.112"
    echo -e "  ${cyan}•${nc} OpenDNS: 208.67.222.222, 208.67.220.220"
    echo ""
}

# Main menu
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}              DNS CHANGER               ${nc}"
echo -e "${red}=========================================${nc}"
echo ""

# Show current DNS
get_current_dns
echo ""

# Show saved DNS if exists
dnsfile="/root/dns"
if test -f "$dnsfile"; then
    udns=$(cat /root/dns)
    echo -e "${green}Saved DNS: $udns${nc}"
    echo ""
fi

show_dns_providers

echo -e " ${cyan}1${nc} Change DNS Server"
echo -e " ${cyan}2${nc} Reset to Default DNS (Google)"
echo -e " ${cyan}3${nc} Use Cloudflare DNS"
echo -e " ${cyan}4${nc} Use Quad9 DNS"
echo -e " ${cyan}5${nc} Reboot after DNS change"
echo -e ""
echo -e " ${white}0${nc} Back To Menu"
echo -e ""
echo -e "${red}=========================================${nc}"
read -p " Select option [0-5]: " dns

case $dns in
    1)
        clear
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}           CHANGE DNS SERVER            ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        show_dns_providers
        read -p "Enter DNS IP (e.g., 1.1.1.1): " dns1
        
        if [[ -z $dns1 ]]; then
            echo -e "${red}Error: DNS cannot be empty!${nc}"
            sleep 2
            clear
            dns
        fi
        
        if ! validate_ip "$dns1"; then
            echo -e "${red}Error: Invalid IP address format!${nc}"
            echo -e "${yellow}Please enter a valid IP (e.g., 1.1.1.1)${nc}"
            sleep 2
            clear
            dns
        fi
        
        # Backup current resolv.conf
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d) 2>/dev/null
        
        # Apply new DNS
        echo -e "${yellow}Applying new DNS configuration...${nc}"
        echo "nameserver $dns1" > /etc/resolv.conf
        echo "$dns1" > /root/dns
        
        # Update resolvconf if exists
        if [ -d /etc/resolvconf/resolv.conf.d/ ]; then
            echo "nameserver $dns1" > /etc/resolvconf/resolv.conf.d/head
            systemctl restart resolvconf.service 2>/dev/null
        fi
        
        echo -e "${green}✓ DNS successfully changed to: $dns1${nc}"
        echo ""
        echo -e "${yellow}New DNS configuration:${nc}"
        cat /etc/resolv.conf
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        clear
        dns
        ;;

    2)
        clear
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}         RESET TO DEFAULT DNS           ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        echo -e "${yellow}This will reset DNS to Google DNS (8.8.8.8)${nc}"
        echo ""
        read -p "Are you sure? [Y/N]: " -e answer
        
        if [[ $answer =~ ^[Yy]$ ]]; then
            # Remove saved DNS
            rm -f /root/dns
            
            # Apply Google DNS
            echo -e "${yellow}Applying Google DNS...${nc}"
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 8.8.4.4" >> /etc/resolv.conf
            
            # Update resolvconf if exists
            if [ -d /etc/resolvconf/resolv.conf.d/ ]; then
                echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/head
                echo "nameserver 8.8.4.4" >> /etc/resolvconf/resolv.conf.d/head
                systemctl restart resolvconf.service 2>/dev/null
            fi
            
            echo -e "${green}✓ DNS successfully reset to Google DNS${nc}"
        else
            echo -e "${yellow}Operation cancelled${nc}"
        fi
        
        sleep 2
        clear
        dns
        ;;

    3)
        clear
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}         APPLY CLOUDFLARE DNS           ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        echo -e "${yellow}Applying Cloudflare DNS (1.1.1.1)...${nc}"
        
        # Apply Cloudflare DNS
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 1.0.0.1" >> /etc/resolv.conf
        echo "1.1.1.1" > /root/dns
        
        # Update resolvconf if exists
        if [ -d /etc/resolvconf/resolv.conf.d/ ]; then
            echo "nameserver 1.1.1.1" > /etc/resolvconf/resolv.conf.d/head
            echo "nameserver 1.0.0.1" >> /etc/resolvconf/resolv.conf.d/head
            systemctl restart resolvconf.service 2>/dev/null
        fi
        
        echo -e "${green}✓ Cloudflare DNS applied successfully${nc}"
        sleep 2
        clear
        dns
        ;;

    4)
        clear
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}            APPLY QUAD9 DNS             ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        echo -e "${yellow}Applying Quad9 DNS (9.9.9.9)...${nc}"
        
        # Apply Quad9 DNS
        echo "nameserver 9.9.9.9" > /etc/resolv.conf
        echo "nameserver 149.112.112.112" >> /etc/resolv.conf
        echo "9.9.9.9" > /root/dns
        
        # Update resolvconf if exists
        if [ -d /etc/resolvconf/resolv.conf.d/ ]; then
            echo "nameserver 9.9.9.9" > /etc/resolvconf/resolv.conf.d/head
            echo "nameserver 149.112.112.112" >> /etc/resolvconf/resolv.conf.d/head
            systemctl restart resolvconf.service 2>/dev/null
        fi
        
        echo -e "${green}✓ Quad9 DNS applied successfully${nc}"
        sleep 2
        clear
        dns
        ;;

    5)
        clear
        echo -e "${blue}=========================================${nc}"
        echo -e "${blue}               REBOOT SYSTEM            ${nc}"
        echo -e "${blue}=========================================${nc}"
        echo ""
        echo -e "${yellow}Rebooting system to apply DNS changes...${nc}"
        echo ""
        echo -e "${red}System will reboot in 5 seconds...${nc}"
        echo -e "${yellow}Press Ctrl+C to cancel${nc}"
        
        for i in {5..1}; do
            echo -e "Rebooting in $i seconds..."
            sleep 1
        done
        
        echo -e "${green}Rebooting now!${nc}"
        /sbin/reboot
        ;;

    0)
        clear
        m-system
        ;;

    *)
        echo -e "${red}Invalid option!${nc}"
        sleep 1
        clear
        dns
        ;;
esac

