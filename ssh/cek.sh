#!/bin/bash
# =========================================
# SSH USER LOGIN MONITOR
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# Temporary files
TMP_DB="/tmp/login-db.txt"
TMP_DB_PID="/tmp/login-db-pid.txt"

cleanup() {
    rm -f "$TMP_DB" "$TMP_DB_PID" /tmp/vpn-login-tcp.txt /tmp/vpn-login-udp.txt 2>/dev/null
}

display_login_info() {
    clear

    # Determine log file location
    if [ -e "/var/log/auth.log" ]; then
        LOG="/var/log/auth.log"
    elif [ -e "/var/log/secure" ]; then
        LOG="/var/log/secure"
    else
        echo -e "${red}Error: No authentication log file found${nc}"
        echo -e "${yellow}Checked: /var/log/auth.log and /var/log/secure${nc}"
        return 1
    fi

    # Dropbear User Login
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}         Dropbear User Login       ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${white}ID  |  Username  |  IP Address${nc}"
    echo -e "${red}=========================================${nc}"

    # Get current Dropbear processes
    mapfile -t dropbear_pids < <(ps aux | grep -i dropbear | grep -v grep | awk '{print $2}' 2>/dev/null)
    
    if [ ${#dropbear_pids[@]} -eq 0 ]; then
        echo -e "${yellow}No active Dropbear connections${nc}"
    else
        # Parse log once for efficiency
        grep -i "dropbear.*Password auth succeeded" "$LOG" 2>/dev/null > "$TMP_DB"
        
        db_count=0
        for pid in "${dropbear_pids[@]}"; do
            if grep -q "dropbear\[$pid\]" "$TMP_DB" 2>/dev/null; then
                user=$(grep "dropbear\[$pid\]" "$TMP_DB" | awk '{print $10}' | sed "s/'//g")
                ip=$(grep "dropbear\[$pid\]" "$TMP_DB" | awk '{print $12}')
                if [[ -n "$user" && -n "$ip" ]]; then
                    printf "${white}%-5s - %-10s - %-15s${nc}\n" "$pid" "$user" "$ip"
                    ((db_count++))
                fi
            fi
        done
        
        if [ $db_count -eq 0 ]; then
            echo -e "${yellow}No authenticated Dropbear users found${nc}"
        fi
    fi
    echo -e "${red}=========================================${nc}"

    echo ""

    # OpenSSH User Login
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}          OpenSSH User Login       ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${white}ID  |  Username  |  IP Address${nc}"
    echo -e "${red}=========================================${nc}"

    # Get current SSH processes
    mapfile -t ssh_pids < <(ps aux | grep "sshd.*@" | grep -v grep | awk '{print $2}' 2>/dev/null)
    
    if [ ${#ssh_pids[@]} -eq 0 ]; then
        echo -e "${yellow}No active SSH connections${nc}"
    else
        # Parse log once for efficiency
        grep -i "sshd.*Accepted password for" "$LOG" 2>/dev/null > "$TMP_DB"
        
        ssh_count=0
        for pid in "${ssh_pids[@]}"; do
            # Find the parent SSH daemon PID
            parent_pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
            if [[ -n "$parent_pid" ]]; then
                if grep -q "sshd\[$parent_pid\]" "$TMP_DB" 2>/dev/null; then
                    user=$(grep "sshd\[$parent_pid\]" "$TMP_DB" | awk '{print $9}')
                    ip=$(grep "sshd\[$parent_pid\]" "$TMP_DB" | awk '{print $11}')
                    if [[ -n "$user" && -n "$ip" ]]; then
                        printf "${white}%-5s - %-10s - %-15s${nc}\n" "$pid" "$user" "$ip"
                        ((ssh_count++))
                    fi
                fi
            fi
        done
        
        if [ $ssh_count -eq 0 ]; then
            echo -e "${yellow}No authenticated SSH users found${nc}"
        fi
    fi
    echo -e "${red}=========================================${nc}"
}

# Main execution
display_login_info

echo ""
echo -e "${red}=========================================${nc}"
echo -e "${blue}              MENU OPTIONS              ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Refresh Login Information"
echo -e "${white}2${nc} Kill User Session"
echo -e "${white}3${nc} Back to SSH Menu"
echo -e "${white}4${nc} Exit"
echo -e "${red}=========================================${nc}"
echo ""

# Menu options
read -p "Select option [1-4]: " option

case $option in
    1)
        cleanup
        exec "$0"
        ;;
    2)
        read -p "Enter PID to kill: " kill_pid
        if [[ "$kill_pid" =~ ^[0-9]+$ ]] && kill -0 "$kill_pid" 2>/dev/null; then
            kill "$kill_pid"
            echo -e "${green}Session $kill_pid terminated${nc}"
            sleep 2
        else
            echo -e "${red}Invalid PID or process not found${nc}"
            sleep 2
        fi
        exec "$0"
        ;;
    3)
        echo -e "${green}Returning to SSH Menu...${nc}"
        sleep 1
        cleanup
        m-sshovpn
        ;;
    4)
        echo -e "${green}Exiting...${nc}"
        sleep 1
        cleanup
        clear
        exit 0
        ;;
    *)
        echo -e "${red}Invalid option!${nc}"
        sleep 2
        exec "$0"
        ;;
esac
