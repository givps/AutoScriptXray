#!/bin/bash
# =========================================
# SSH AUTOKILL MENU - HAPROXY WEBSOCKET VERSION
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# Configuration
AUTOKILL_SCRIPT="/usr/bin/autokill-ws"  # Updated script path
LOG_FILE="/var/log/autokill.log"

clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}        AUTOKILL SSH MENU - HAProxy WS ${nc}"
echo -e "${red}=========================================${nc}"

# Function to create autokill script
create_autokill_script() {
    cat > $AUTOKILL_SCRIPT << 'EOF'
#!/bin/bash
# =========================================
# AUTOKILL SCRIPT - HAPROXY WEBSOCKET
# =========================================

MAX_CONN=$1
LOG_FILE="/var/log/autokill.log"

# Colors for log
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
nc='\e[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# Get current SSH connections (including WebSocket)
get_ssh_connections() {
    # Get SSH connections from netstat (direct SSH)
    netstat -tn 2>/dev/null | grep ':22 ' | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | awk '{print $2":"$1}'
    
    # Get HAProxy WebSocket connections
    if netstat -tn 2>/dev/null | grep -q ':1443\|:1444'; then
        netstat -tn 2>/dev/null | grep -E ':1443|:1444' | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | awk '{print $2":"$1}'
    fi
}

# Kill user processes and connections
kill_user_connections() {
    local user=$1
    local ip=$2
    local connections=$3
    
    log "KILLING: User $user from $IP with $connections connections (Max: $MAX_CONN)"
    
    # Kill all user processes
    pkill -9 -u $user 2>/dev/null
    
    # Kill specific SSH sessions
    ps aux | grep "^$user" | grep -E "ssh|dropbear" | awk '{print $2}' | xargs kill -9 2>/dev/null
    
    # Block IP temporarily using iptables
    iptables -I INPUT -s $ip -p tcp --dport 22 -j DROP 2>/dev/null
    iptables -I INPUT -s $ip -p tcp --dport 1443 -j DROP 2>/dev/null
    iptables -I INPUT -s $ip -p tcp --dport 1444 -j DROP 2>/dev/null
    iptables -I INPUT -s $ip -p tcp --dport 1445 -j DROP 2>/dev/null
    iptables -I INPUT -s $ip -p tcp --dport 1446 -j DROP 2>/dev/null
    
    # Remove block after 10 minutes
    echo "iptables -D INPUT -s $ip -p tcp --dport 22 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
    echo "iptables -D INPUT -s $ip -p tcp --dport 1443 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
    echo "iptables -D INPUT -s $ip -p tcp --dport 1444 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
    echo "iptables -D INPUT -s $ip -p tcp --dport 1445 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
    echo "iptables -D INPUT -s $ip -p tcp --dport 1446 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
}

# Main autokill logic
main() {
    if [ -z "$MAX_CONN" ] || ! [[ "$MAX_CONN" =~ ^[0-9]+$ ]]; then
        log "ERROR: Invalid max connections parameter"
        exit 1
    fi
    
    log "=== AUTOKILL RUN (Max: $MAX_CONN) ==="
    
    # Get all connections and process by IP
    get_ssh_connections | while IFS=: read ip count; do
        if [ -n "$ip" ] && [ "$count" -gt "$MAX_CONN" ]; then
            # Find username from this IP
            username=$(who | grep "$ip" | awk '{print $1}' | head -1)
            
            if [ -z "$username" ]; then
                # Try to find from netstat process
                username=$(netstat -tnp 2>/dev/null | grep "$ip" | grep -E ':22|:1443|:1444' | awk '{print $7}' | cut -d'/' -f2 | head -1)
            fi
            
            if [ -n "$username" ] && [ "$username" != "root" ]; then
                kill_user_connections "$username" "$ip" "$count"
            else
                log "UNKNOWN USER from $IP with $count connections"
                # Block IP anyway
                iptables -I INPUT -s $ip -p tcp --dport 22 -j DROP 2>/dev/null
                iptables -I INPUT -s $ip -p tcp --dport 1443 -j DROP 2>/dev/null
                iptables -I INPUT -s $ip -p tcp --dport 1444 -j DROP 2>/dev/null
                echo "iptables -D INPUT -s $ip -p tcp --dport 22 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
                echo "iptables -D INPUT -s $ip -p tcp --dport 1443 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
                echo "iptables -D INPUT -s $ip -p tcp --dport 1444 -j DROP 2>/dev/null" | at now + 10 minutes 2>/dev/null
            fi
        fi
    done
    
    log "=== AUTOKILL COMPLETED ==="
}

main "$@"
EOF

    chmod +x $AUTOKILL_SCRIPT
}

# Check status with better detection
echo -e "${blue}📊 Current Status:${nc}"
if [ -f "/etc/cron.d/autokill-ws" ] && grep -q "autokill-ws" "/etc/cron.d/autokill-ws" 2>/dev/null; then
    echo -e "Autokill Status  : ${green}[ACTIVE]${nc}"
    
    # Show current settings
    cron_line=$(grep -E "^\*/[0-9]+" /etc/cron.d/autokill-ws | head -1)
    if [[ $cron_line =~ \*/[0-9]+\ \*\ \*\ \*\ \*\ root\ $AUTOKILL_SCRIPT\ ([0-9]+) ]]; then
        interval=${cron_line#*/}
        interval=${interval%% *}
        max_conn=${BASH_REMATCH[1]}
        echo -e "Check Interval    : ${yellow}Every $interval minutes${nc}"
        echo -e "Max Connections   : ${yellow}$max_conn per user${nc}"
    fi
    
    # Show recent activity
    if [ -f "$LOG_FILE" ]; then
        recent_kills=$(tail -5 "$LOG_FILE" | grep "KILLING:" | wc -l)
        echo -e "Recent Actions    : ${red}$recent_kills kills in last check${nc}"
    fi
else
    echo -e "Autokill Status  : ${red}[INACTIVE]${nc}"
fi

# Show current connections
echo -e ""
echo -e "${blue}🔍 Current Connections:${nc}"
current_conn=$(netstat -tn 2>/dev/null | grep -E ':22|:1443|:1444' | grep ESTABLISHED | wc -l)
echo -e "Total SSH/WS Connections: ${yellow}$current_conn${nc}"

echo -e ""
echo -e "${blue}🎯 Autokill Options:${nc}"
echo -e "${white}1${nc} AutoKill Every 5 Minutes"
echo -e "${white}2${nc} AutoKill Every 10 Minutes" 
echo -e "${white}3${nc} AutoKill Every 15 Minutes"
echo -e "${white}4${nc} AutoKill Every 30 Minutes"
echo -e "${white}5${nc} Custom Interval"
echo -e "${white}6${nc} View Autokill Log"
echo -e "${white}7${nc} Clear Autokill Log"
echo -e "${white}8${nc} Manual Kill User"
echo -e "${white}9${nc} Turn Off AutoKill"
echo -e "${white}0${nc} Back to SSH Menu"
echo -e "${white}x${nc} Exit"
echo -e ""
echo -e "${red}=========================================${nc}"
echo -e ""

read -p "Select option [0-9 or x]: " AutoKill

# Ensure autokill script exists
if [[ "$AutoKill" =~ ^[1-5]$ ]] && [ ! -f "$AUTOKILL_SCRIPT" ]; then
    echo -e "${yellow}Creating autokill script...${nc}"
    create_autokill_script
    echo -e "${green}✓ Autokill script created at $AUTOKILL_SCRIPT${nc}"
fi

case $AutoKill in
    1|2|3)
        case $AutoKill in
            1) interval=5 ;;
            2) interval=10 ;;
            3) interval=15 ;;
        esac
        
        while true; do
            read -p "Max connections allowed per user [1-20]: " max
            if [[ "$max" =~ ^[1-9]$|^1[0-9]$|^20$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-20${nc}"
            fi
        done
        
        # Create cron entry
        cat > /etc/cron.d/autokill-ws << EOF
# AutoKill HAProxy WebSocket - Do not edit manually
# Check every $interval minutes, max $max connections per user
*/$interval * * * * root $AUTOKILL_SCRIPT $max
EOF
        
        echo -e "${green}✅ AutoKill activated${nc}"
        echo -e "  Check interval : Every $interval minutes"
        echo -e "  Max connections: $max per user"
        echo -e "  Protected ports : 22, 1443, 1444, 1445, 1446"
        ;;
        
    4)
        while true; do
            read -p "Max connections allowed per user [1-20]: " max
            if [[ "$max" =~ ^[1-9]$|^1[0-9]$|^20$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-20${nc}"
            fi
        done
        
        cat > /etc/cron.d/autokill-ws << EOF
# AutoKill HAProxy WebSocket - Do not edit manually
# Check every 30 minutes, max $max connections per user
*/30 * * * * root $AUTOKILL_SCRIPT $max
EOF
        
        echo -e "${green}✅ AutoKill activated${nc}"
        echo -e "  Check interval : Every 30 minutes"
        echo -e "  Max connections: $max per user"
        ;;
        
    5)
        while true; do
            read -p "Check interval in minutes [1-60]: " interval
            if [[ "$interval" =~ ^[1-9]$|^[1-5][0-9]$|^60$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-60${nc}"
            fi
        done
        
        while true; do
            read -p "Max connections allowed per user [1-20]: " max
            if [[ "$max" =~ ^[1-9]$|^1[0-9]$|^20$ ]]; then
                break
            else
                echo -e "${red}Please enter a number between 1-20${nc}"
            fi
        done
        
        cat > /etc/cron.d/autokill-ws << EOF
# AutoKill HAProxy WebSocket - Do not edit manually
# Check every $interval minutes, max $max connections per user
*/$interval * * * * root $AUTOKILL_SCRIPT $max
EOF
        
        echo -e "${green}✅ AutoKill activated${nc}"
        echo -e "  Check interval : Every $interval minutes"
        echo -e "  Max connections: $max per user"
        ;;
        
    6)
        # View autokill log
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}            AUTOKILL LOG               ${nc}"
        echo -e "${red}=========================================${nc}"
        if [ -f "$LOG_FILE" ]; then
            tail -20 "$LOG_FILE"
        else
            echo -e "${yellow}No autokill log found${nc}"
        fi
        echo -e "${red}=========================================${nc}"
        read -n 1 -s -r -p "Press any key to continue..."
        $0
        ;;
        
    7)
        # Clear autokill log
        if [ -f "$LOG_FILE" ]; then
            rm -f "$LOG_FILE"
            echo -e "${green}✓ Autokill log cleared${nc}"
        else
            echo -e "${yellow}No autokill log to clear${nc}"
        fi
        sleep 2
        $0
        ;;
        
    8)
        # Manual kill user
        clear
        echo -e "${red}=========================================${nc}"
        echo -e "${blue}            MANUAL KILL USER           ${nc}"
        echo -e "${red}=========================================${nc}"
        echo ""
        
        # Show current users with connections
        echo -e "${yellow}Current Users with Connections:${nc}"
        who | awk '{print $1}' | sort | uniq | while read user; do
            conn_count=$(who | grep "^$user" | wc -l)
            echo -e "  $user - $conn_count connections"
        done
        
        echo ""
        read -p "Enter username to kill: " kill_user
        
        if getent passwd "$kill_user" >/dev/null 2>&1; then
            echo -e "${yellow}Killing all connections for user: $kill_user${nc}"
            pkill -9 -u "$kill_user"
            echo -e "${green}✓ All connections killed for $kill_user${nc}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Manual kill: $kill_user" >> "$LOG_FILE"
        else
            echo -e "${red}User $kill_user not found${nc}"
        fi
        
        read -n 1 -s -r -p "Press any key to continue..."
        $0
        ;;
        
    9)
        # Turn off autokill
        if [ -f "/etc/cron.d/autokill-ws" ]; then
            rm -f /etc/cron.d/autokill-ws
            echo -e "${yellow}✓ AutoKill disabled${nc}"
        else
            echo -e "${yellow}AutoKill was already inactive${nc}"
        fi
        ;;
        
    0)
        echo -e "${green}Returning to SSH Menu...${nc}"
        sleep 1
        m-sshovpn
        exit 0
        ;;
        
    x)
        clear
        exit 0
        ;;
        
    *)
        echo -e "${red}Invalid option!${nc}"
        sleep 2
        $0
        ;;
esac

# Reload cron configuration
echo -e "${yellow}Reloading cron configuration...${nc}"
if command -v systemctl >/dev/null 2>&1; then
    systemctl reload cron >/dev/null 2>&1 || systemctl reload crond >/dev/null 2>&1
else
    service cron reload >/dev/null 2>&1 || service crond reload >/dev/null 2>&1
fi

echo ""
read -n 1 -s -r -p "Press any key to return to AutoKill menu..."
$0