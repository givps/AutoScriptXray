#!/bin/bash
# =========================================
# CEK USER - HAPROXY WEBSOCKET VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# System info
MYIP=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "IP_NOT_FOUND")
DOMAIN=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null || echo "no-domain.com")

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}           CEK USER - HAProxy WS        ${nc}"
echo -e "${red}=========================================${nc}"

# Function to show user list
show_user_list() {
    echo -e "${yellow}📋 DAFTAR USER SSH:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    total_users=0
    expired_users=0
    active_users=0
    
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read user; do
        if [ "$user" != "sync" ] && [ "$user" != "halt" ]; then
            ((total_users++))
            
            # Check expiry
            expiry=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            if [ "$expiry" = "never" ]; then
                status="${green}ACTIVE${nc}"
                ((active_users++))
            else
                expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
                today_sec=$(date +%s)
                if [ $expiry_sec -lt $today_sec ]; then
                    status="${red}EXPIRED${nc}"
                    ((expired_users++))
                else
                    days_left=$(( (expiry_sec - today_sec) / 86400 ))
                    status="${yellow}$days_left day(s)${nc}"
                    ((active_users++))
                fi
            fi
            
            # Check if user is currently connected
            connections=$(who | grep "^$user" | wc -l)
            if [ $connections -gt 0 ]; then
                conn_status="${green}✅ Online ($connections)${nc}"
            else
                conn_status="${white}❌ Offline${nc}"
            fi
            
            echo -e " ${white}•${nc} $user - Status: $status - $conn_status"
        fi
    done
    
    echo -e "${blue}=========================================${nc}"
    echo -e "Total Users    : ${green}$total_users${nc}"
    echo -e "Active Users   : ${green}$active_users${nc}"
    echo -e "Expired Users  : ${red}$expired_users${nc}"
    echo -e "${blue}=========================================${nc}"
}

# Function to show user details
show_user_details() {
    echo ""
    echo -e "${yellow}🔍 DETAIL USER:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    read -p "Masukkan username: " username
    
    if getent passwd "$username" >/dev/null 2>&1; then
        user_info=$(getent passwd "$username")
        user_shell=$(echo "$user_info" | cut -d: -f7)
        user_home=$(echo "$user_info" | cut -d: -f6)
        user_group=$(id -gn "$username")
        
        expiry=$(chage -l "$username" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        last_login=$(lastlog -u "$username" 2>/dev/null | tail -1 | awk '{print $4" "$5" "$6" "$7" "$8}')
        
        # Current connections
        connections=$(who | grep "^$username" | wc -l)
        connection_ips=$(who | grep "^$username" | awk '{print $5}' | sed 's/(//g; s/)//g' | tr '\n' ',' | sed 's/,$//')
        
        echo -e "Username        : ${green}$username${nc}"
        echo -e "Shell           : ${white}$user_shell${nc}"
        echo -e "Home Directory  : ${white}$user_home${nc}"
        echo -e "Group           : ${white}$user_group${nc}"
        echo -e "Account Expires : ${yellow}$expiry${nc}"
        echo -e "Last Login      : ${cyan}$last_login${nc}"
        echo -e "Current Status  : $([ $connections -gt 0 ] && echo "${green}✅ Online ($connections connections)${nc}" || echo "${white}❌ Offline${nc}")"
        
        if [ $connections -gt 0 ]; then
            echo -e "Connected From  : ${yellow}$connection_ips${nc}"
        fi
        
        # Show login history
        echo -e "${blue}-----------------------------------------${nc}"
        echo -e "${yellow}📊 Login History (Last 5):${nc}"
        last -5 "$username" | head -5 | while read line; do
            if [ -n "$line" ] && ! echo "$line" | grep -q "still logged in"; then
                echo -e "  ${white}$line${nc}"
            fi
        done
        
    else
        echo -e "${red}❌ User $username tidak ditemukan${nc}"
    fi
    
    echo -e "${blue}=========================================${nc}"
}

# Function to show active connections
show_active_connections() {
    echo ""
    echo -e "${yellow}🌐 KONEKSI AKTIF:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    # SSH Direct connections
    echo -e "${green}🔌 SSH Direct Connections:${nc}"
    netstat -tn 2>/dev/null | grep ':22 ' | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | while read count ip; do
        user=$(who | grep "$ip" | awk '{print $1}' | head -1)
        if [ -z "$user" ]; then
            user="UNKNOWN"
        fi
        echo -e "  $user@$ip - $count connections"
    done
    
    # HAProxy WebSocket connections
    echo -e "${green}🌐 WebSocket Connections:${nc}"
    netstat -tn 2>/dev/null | grep -E ':1443|:1444' | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | while read count ip; do
        # Try to find user from process
        user=$(netstat -tnp 2>/dev/null | grep "$ip" | grep -E ':1443|:1444' | awk '{print $7}' | cut -d'/' -f2 | head -1)
        if [ -z "$user" ] || [ "$user" = "-" ]; then
            user="WS_USER"
        fi
        echo -e "  $user@$ip - $count connections"
    done
    
    # Total connections
    total_ssh=$(netstat -tn 2>/dev/null | grep ':22 ' | grep ESTABLISHED | wc -l)
    total_ws=$(netstat -tn 2>/dev/null | grep -E ':1443|:1444' | grep ESTABLISHED | wc -l)
    
    echo -e "${blue}-----------------------------------------${nc}"
    echo -e "Total SSH Direct  : ${yellow}$total_ssh${nc}"
    echo -e "Total WebSocket   : ${yellow}$total_ws${nc}"
    echo -e "Total Connections : ${green}$((total_ssh + total_ws))${nc}"
    echo -e "${blue}=========================================${nc}"
}

# Function to show system statistics
show_system_stats() {
    echo ""
    echo -e "${yellow}📊 SYSTEM STATISTICS:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    # Server info
    echo -e "${green}🖥️  Server Info:${nc}"
    echo -e "IP Address    : ${white}$MYIP${nc}"
    echo -e "Domain        : ${white}$DOMAIN${nc}"
    echo -e "Uptime        : ${yellow}$(uptime -p | sed 's/up //')${nc}"
    
    # Service status
    echo -e "${green}🔧 Service Status:${nc}"
    echo -e "OpenSSH       : $(systemctl is-active ssh >/dev/null 2>&1 && echo '✅' || echo '❌')"
    echo -e "HAProxy       : $(systemctl is-active haproxy >/dev/null 2>&1 && echo '✅' || echo '❌')"
    echo -e "WebSocket Proxy: $(systemctl is-active ws-proxy >/dev/null 2>&1 && echo '✅' || echo '❌')"
    
    # Resource usage
    echo -e "${green}📈 Resource Usage:${nc}"
    echo -e "CPU Load      : ${yellow}$(uptime | awk -F'load average:' '{print $2}')${nc}"
    echo -e "Memory Usage  : ${yellow}$(free -h | grep Mem | awk '{print $3"/"$2}')${nc}"
    echo -e "Disk Usage    : ${yellow}$(df -h / | tail -1 | awk '{print $3"/"$2 " ("$5")"}')${nc}"
    
    echo -e "${blue}=========================================${nc}"
}

# Function to show expired users
show_expired_users() {
    echo ""
    echo -e "${red}⏰ USER EXPIRED:${nc}"
    echo -e "${blue}=========================================${nc}"
    
    expired_count=0
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read user; do
        if [ "$user" != "sync" ] && [ "$user" != "halt" ]; then
            expiry=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            if [ "$expiry" != "never" ]; then
                expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
                today_sec=$(date +%s)
                if [ $expiry_sec -lt $today_sec ]; then
                    echo -e " ${red}•${nc} $user - Expired: $expiry"
                    ((expired_count++))
                fi
            fi
        fi
    done
    
    if [ $expired_count -eq 0 ]; then
        echo -e "${green}Tidak ada user yang expired${nc}"
    else
        echo -e "${blue}-----------------------------------------${nc}"
        echo -e "Total Expired Users: ${red}$expired_count${nc}"
    fi
    
    echo -e "${blue}=========================================${nc}"
}

# Function to show users expiring soon
show_expiring_soon() {
    echo ""
    echo -e "${yellow}⚠️  USER AKAN EXPIRED (3 hari):${nc}"
    echo -e "${blue}=========================================${nc}"
    
    expiring_count=0
    getent passwd | grep -E ":/bin/false$" | cut -d: -f1 | while read user; do
        if [ "$user" != "sync" ] && [ "$user" != "halt" ]; then
            expiry=$(chage -l $user 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            if [ "$expiry" != "never" ]; then
                expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
                today_sec=$(date +%s)
                days_left=$(( (expiry_sec - today_sec) / 86400 ))
                if [ $days_left -le 3 ] && [ $days_left -ge 0 ]; then
                    echo -e " ${yellow}•${nc} $user - $days_left hari lagi"
                    ((expiring_count++))
                fi
            fi
        fi
    done
    
    if [ $expiring_count -eq 0 ]; then
        echo -e "${green}Tidak ada user yang akan expired dalam 3 hari${nc}"
    else
        echo -e "${blue}-----------------------------------------${nc}"
        echo -e "Total Akan Expired: ${yellow}$expiring_count${nc}"
    fi
    
    echo -e "${blue}=========================================${nc}"
}

# Main menu
main_menu() {
    echo ""
    echo -e "${blue}🎯 MENU CEK USER:${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${white}1${nc} Lihat Daftar User"
    echo -e "${white}2${nc} Detail User"
    echo -e "${white}3${nc} Koneksi Aktif"
    echo -e "${white}4${nc} Statistik Sistem"
    echo -e "${white}5${nc} User Expired"
    echo -e "${white}6${nc} User Akan Expired"
    echo -e "${white}7${nc} Refresh"
    echo -e "${white}0${nc} Kembali ke Menu SSH"
    echo -e "${white}x${nc} Exit"
    echo -e "${red}=========================================${nc}"
    echo ""
    
    read -p "Pilih opsi [0-7 atau x]: " option
    
    case $option in
        1)
            show_user_list
            main_menu
            ;;
        2)
            show_user_details
            main_menu
            ;;
        3)
            show_active_connections
            main_menu
            ;;
        4)
            show_system_stats
            main_menu
            ;;
        5)
            show_expired_users
            main_menu
            ;;
        6)
            show_expiring_soon
            main_menu
            ;;
        7)
            exec $0
            ;;
        0)
            echo -e "${green}Kembali ke Menu SSH...${nc}"
            sleep 1
            m-sshovpn
            ;;
        x)
            clear
            exit 0
            ;;
        *)
            echo -e "${red}Pilihan tidak valid!${nc}"
            sleep 2
            main_menu
            ;;
    esac
}

# Initial display
show_system_stats
show_user_list
show_active_connections
main_menu