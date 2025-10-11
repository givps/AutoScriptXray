#!/bin/bash
# =========================================
# AUTO INSTALL TORRENT BLOCKER
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
nc='\e[0m'

# Configuration
SCRIPT_NAME="auto-torrent-blocker.sh"
INSTALL_DIR="/usr/local/torrent-blocker"
LOG_FILE="/var/log/torrent-blocker.log"

# Function to print status
print_status() {
    echo -e "${blue}[INFO]${nc} $1"
}

print_success() {
    echo -e "${green}[SUCCESS]${nc} $1"
}

print_warning() {
    echo -e "${yellow}[WARNING]${nc} $1"
}

print_error() {
    echo -e "${red}[ERROR]${nc} $1"
}

# Function to check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    print_status "Checking system dependencies..."
    
    local missing_deps=()
    
    # Check for required commands
    for cmd in iptables grep awk; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        print_success "All dependencies are installed"
        return 0
    fi
    
    print_warning "Installing missing dependencies: ${missing_deps[*]}"
    
    # Detect package manager and install dependencies
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        apt-get update -q
        apt-get install -y -q iptables netfilter-persistent iptables-persistent
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        yum install -y -q iptables iptables-services
    elif command -v dnf &> /dev/null; then
        # Fedora
        dnf install -y -q iptables iptables-services
    else
        print_error "Could not automatically install dependencies"
        return 1
    fi
    
    print_success "Dependencies installed successfully"
    return 0
}

# Function to backup current iptables rules
backup_iptables() {
    local backup_dir="/etc/iptables/backups"
    local backup_file="$backup_dir/backup.$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$backup_dir"
    iptables-save > "$backup_file"
    print_success "Iptables backup created: $backup_file"
    echo "$backup_file"
}

# Function to check existing torrent rules
check_existing_torrent_rules() {
    if iptables -L FORWARD -n 2>/dev/null | grep -q "BitTorrent\|torrent"; then
        return 0
    else
        return 1
    fi
}

# Function to remove existing torrent rules
remove_existing_torrent_rules() {
    print_status "Cleaning existing torrent rules..."
    
    # Remove string matching rules from FORWARD chain
    local patterns=(
        "get_peers"
        "announce_peer" 
        "find_node"
        "BitTorrent"
        "BitTorrent protocol"
        "peer_id="
        ".torrent"
        "announce.php?passkey="
        "torrent"
        "announce"
        "info_hash"
        "magnet:"
        "x-bittorrent"
        "application/x-bittorrent"
    )
    
    for pattern in "${patterns[@]}"; do
        # Remove from FORWARD chain
        while true; do
            local line_num=$(iptables -L FORWARD --line-numbers -n 2>/dev/null | grep "$pattern" | head -1 | awk '{print $1}')
            [[ -z "$line_num" ]] && break
            iptables -D FORWARD "$line_num" 2>/dev/null
        done
        
        # Remove from INPUT chain  
        while true; do
            local line_num=$(iptables -L INPUT --line-numbers -n 2>/dev/null | grep "$pattern" | head -1 | awk '{print $1}')
            [[ -z "$line_num" ]] && break
            iptables -D INPUT "$line_num" 2>/dev/null
        done
        
        # Remove from OUTPUT chain
        while true; do
            local line_num=$(iptables -L OUTPUT --line-numbers -n 2>/dev/null | grep "$pattern" | head -1 | awk '{print $1}')
            [[ -z "$line_num" ]] && break
            iptables -D OUTPUT "$line_num" 2>/dev/null
        done
    done
    
    print_success "Existing torrent rules cleaned"
}

# Function to block torrent ports
block_torrent_ports() {
    print_status "Blocking common torrent ports..."
    
    # Common BitTorrent and P2P ports
    local torrent_ports=(
        "6881:6889"  # Traditional BitTorrent
        "1337"       # Common torrent
        "4444"       # Common torrent  
        "8888"       # Common torrent
        "9999"       # Common torrent
        "10000"      # Common torrent
        "25252"      # Common torrent
        "4662"       # eDonkey
        "4672"       # eDonkey
        "6346"       # Gnutella
        "6347"       # Gnutella
        "6699"       # Napster
        "6771"       # WinMX
        "7777"       # P2P
    )
    
    for port in "${torrent_ports[@]}"; do
        # Block incoming connections
        iptables -A INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
        iptables -A INPUT -p udp --dport "$port" -j DROP 2>/dev/null
        
        # Block outgoing connections  
        iptables -A OUTPUT -p tcp --dport "$port" -j DROP 2>/dev/null
        iptables -A OUTPUT -p udp --dport "$port" -j DROP 2>/dev/null
        
        # Block forwarded connections
        iptables -A FORWARD -p tcp --dport "$port" -j DROP 2>/dev/null
        iptables -A FORWARD -p udp --dport "$port" -j DROP 2>/dev/null
    done
    
    print_success "Torrent ports blocked"
}

# Function to block torrent traffic by string matching
block_torrent_strings() {
    print_status "Blocking torrent traffic patterns..."
    
    # BitTorrent protocol strings
    iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
    iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
    iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
    iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP
    iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP
    iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP
    iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP
    iptables -A FORWARD -m string --algo bm --string "announce.php?passkey=" -j DROP
    iptables -A FORWARD -m string --algo bm --string "torrent" -j DROP
    iptables -A FORWARD -m string --algo bm --string "announce" -j DROP
    iptables -A FORWARD -m string --algo bm --string "info_hash" -j DROP
    iptables -A FORWARD -m string --algo bm --string "magnet:" -j DROP
    iptables -A FORWARD -m string --algo bm --string "x-bittorrent" -j DROP
    iptables -A FORWARD -m string --algo bm --string "application/x-bittorrent" -j DROP
    
    # Additional P2P protocols
    iptables -A FORWARD -m string --algo bm --string "ed2k://" -j DROP
    iptables -A FORWARD -m string --algo bm --string "gnutella" -j DROP
    
    # Also block in INPUT and OUTPUT for local protection
    iptables -A INPUT -m string --algo bm --string "BitTorrent" -j DROP
    iptables -A OUTPUT -m string --algo bm --string "BitTorrent" -j DROP
    
    print_success "Torrent traffic patterns blocked"
}

# Function to save iptables rules persistently
save_iptables_rules() {
    print_status "Making iptables rules persistent..."
    
    # Save current rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    # Try different persistence methods
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
        print_success "Rules saved with netfilter-persistent"
    elif command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/sysconfig/iptables
        print_success "Rules saved to /etc/sysconfig/iptables"
    fi
    
    # Create systemd service for auto-restore
    cat > /etc/systemd/system/iptables-torrent-block.service << EOF
[Unit]
Description=IPTables Torrent Block Rules
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables-restore < /etc/iptables/rules.v4
ExecReload=/sbin/iptables-restore < /etc/iptables/rules.v4

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable iptables-torrent-block.service >/dev/null 2>&1
    
    print_success "Iptables rules made persistent"
}

# Function to create monitoring script
create_monitoring_script() {
    print_status "Creating monitoring tools..."
    
    mkdir -p "$INSTALL_DIR"
    
    # Main monitoring script
    cat > "$INSTALL_DIR/monitor-torrent.sh" << 'EOF'
#!/bin/bash
# Torrent Blocker Monitor

echo "=== Torrent Blocker Status ==="
echo ""

# Check if rules are active
echo "📊 Active Torrent Blocking Rules:"
echo "----------------------------------"
iptables -L FORWARD -n | grep -c "STRING"
echo " rules in FORWARD chain"

echo ""
echo "🔍 Recent Blocked Attempts:"
echo "----------------------------------"
dmesg | grep -i "bit torrent\|bittorrent\|torrent" | tail -3

echo ""
echo "🌐 Connections on Torrent Ports:"
echo "----------------------------------"
netstat -tulpn 2>/dev/null | grep -E ":6881|:6882|:6883|:6884|:6885|:6886|:6887|:6888|:6889" | head -5

echo ""
echo "📈 Rule Statistics:"
echo "----------------------------------"
iptables -L FORWARD -n -v | head -10
EOF

    chmod +x "$INSTALL_DIR/monitor-torrent.sh"
    ln -sf "$INSTALL_DIR/monitor-torrent.sh" /usr/local/bin/torrent-status
    
    # Create log rotation
    cat > /etc/logrotate.d/torrent-blocker << EOF
/var/log/torrent-blocker.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

    print_success "Monitoring tools created"
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    local success=0
    
    # Check if rules are applied
    if iptables -L FORWARD -n 2>/dev/null | grep -q "STRING"; then
        print_success "Torrent blocking rules are active"
        success=1
    else
        print_error "No torrent blocking rules found"
    fi
    
    # Check if monitoring script exists
    if [[ -f "/usr/local/bin/torrent-status" ]]; then
        print_success "Monitoring script installed"
    else
        print_warning "Monitoring script not found"
    fi
    
    # Check if rules are persistent
    if [[ -f "/etc/iptables/rules.v4" ]]; then
        print_success "Persistent rules configured"
    else
        print_warning "Persistence not fully configured"
    fi
    
    return $success
}

# Function to show usage information
show_usage_info() {
    echo ""
    echo -e "${green}=========================================${nc}"
    echo -e "${green}     TORRENT BLOCKER INSTALLED         ${nc}"
    echo -e "${green}=========================================${nc}"
    echo ""
    echo -e "${blue}Usage Commands:${nc}"
    echo -e "  Check status  : ${green}torrent-status${nc}"
    echo -e "  View rules    : ${green}iptables -L FORWARD -n${nc}"
    echo -e "  View all rules: ${green}iptables-save${nc}"
    echo ""
    echo -e "${blue}Files Created:${nc}"
    echo -e "  Rules file    : ${yellow}/etc/iptables/rules.v4${nc}"
    echo -e "  Monitor script: ${yellow}$INSTALL_DIR/monitor-torrent.sh${nc}"
    echo -e "  Log file      : ${yellow}$LOG_FILE${nc}"
    echo ""
    echo -e "${green}Torrent traffic is now being blocked!${nc}"
    echo ""
}

# Function to log installation
log_installation() {
    local status=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Torrent blocker installation $status" >> "$LOG_FILE"
}

# Main installation function
auto_install_torrent_blocker() {
    clear
    echo -e "${blue}=========================================${nc}"
    echo -e "${blue}      AUTO TORRENT BLOCKER INSTALLER    ${nc}"
    echo -e "${blue}=========================================${nc}"
    echo ""
    echo -e "${yellow}Starting automatic installation...${nc}"
    echo ""
    
    # Check root privileges
    check_root
    
    # Install dependencies
    if ! install_dependencies; then
        print_error "Failed to install dependencies"
        log_installation "FAILED_DEPENDENCIES"
        exit 1
    fi
    
    # Backup current rules
    backup_file=$(backup_iptables)
    
    # Remove existing torrent rules
    remove_existing_torrent_rules
    
    # Apply torrent blocking
    block_torrent_ports
    block_torrent_strings
    
    # Make rules persistent
    save_iptables_rules
    
    # Create monitoring tools
    create_monitoring_script
    
    # Verify installation
    if verify_installation; then
        print_success "Installation completed successfully!"
        show_usage_info
        log_installation "SUCCESS"
    else
        print_warning "Installation completed with warnings"
        show_usage_info
        log_installation "COMPLETED_WITH_WARNINGS"
    fi
    
    echo ""
    echo -e "${yellow}Installation log: $LOG_FILE${nc}"
    echo -e "${yellow}Backup file: $backup_file${nc}"
    echo ""
}

# Auto-run installation
auto_install_torrent_blocker
