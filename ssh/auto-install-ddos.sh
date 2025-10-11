#!/bin/bash
# =========================================
# AUTO INSTALL DDOS DEFLATE
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
nc='\e[0m'

# Configuration
INSTALL_DIR="/usr/local/ddos"
LOG_DIR="/var/log/ddos"
CRON_JOB="*/1 * * * * root /usr/local/ddos/ddos.sh --cron > /dev/null 2>&1"

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
    for cmd in netstat grep awk sort uniq wget; do
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
        apt-get install -y -q "${missing_deps[@]}" net-tools
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        yum install -y -q "${missing_deps[@]}" net-tools
    elif command -v dnf &> /dev/null; then
        # Fedora
        dnf install -y -q "${missing_deps[@]}" net-tools
    elif command -v apk &> /dev/null; then
        # Alpine
        apk add --no-cache "${missing_deps[@]}" net-tools
    else
        print_error "Could not automatically install dependencies"
        return 1
    fi
    
    print_success "Dependencies installed successfully"
    return 0
}

# Function to remove previous installation
clean_previous_installation() {
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Removing previous installation..."
        rm -rf "$INSTALL_DIR"
        rm -f /usr/local/sbin/ddos
        rm -f /usr/local/sbin/ddos-deflate
        
        # Remove cron job
        if [ -f /etc/cron.d/ddos ]; then
            rm -f /etc/cron.d/ddos
        fi
        
        # Remove from crontab
        crontab -l 2>/dev/null | grep -v 'ddos.sh' | crontab -
        
        print_success "Previous installation cleaned"
    fi
}

# Function to create directories
create_directories() {
    print_status "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    
    print_success "Directories created: $INSTALL_DIR, $LOG_DIR"
}

# Function to download DDOS Deflate
download_ddos_deflate() {
    print_status "Downloading DDOS Deflate files..."
    
    # List of possible download sources
    local sources=(
        "https://raw.githubusercontent.com/jgmdev/ddos-deflate/master/ddos.sh"
        "https://gitlab.com/jgmdev/ddos-deflate/-/raw/master/ddos.sh"
        "https://cdn.jsdelivr.net/gh/jgmdev/ddos-deflate/ddos.sh"
    )
    
    local config_sources=(
        "https://raw.githubusercontent.com/jgmdev/ddos-deflate/master/ddos.conf"
        "https://gitlab.com/jgmdev/ddos-deflate/-/raw/master/ddos.conf"
        "https://cdn.jsdelivr.net/gh/jgmdev/ddos-deflate/ddos.conf"
    )
    
    # Download main script
    for source in "${sources[@]}"; do
        print_status "Trying: $source"
        if wget -q --timeout=10 -O "$INSTALL_DIR/ddos.sh" "$source"; then
            print_success "Downloaded main script"
            break
        fi
    done
    
    # Check if download was successful
    if [ ! -s "$INSTALL_DIR/ddos.sh" ]; then
        print_error "Failed to download main script from all sources"
        return 1
    fi
    
    # Download config file
    for source in "${config_sources[@]}"; do
        if wget -q --timeout=10 -O "$INSTALL_DIR/ddos.conf" "$source"; then
            print_success "Downloaded config file"
            break
        fi
    done
    
    # If config download failed, create a default one
    if [ ! -s "$INSTALL_DIR/ddos.conf" ]; then
        print_warning "Creating default config file"
        create_default_config
    fi
    
    return 0
}

# Function to create default config
create_default_config() {
    cat > "$INSTALL_DIR/ddos.conf" << 'EOF'
# DDOS Deflate Configuration File
# Paths and files
PROGDIR="/usr/local/ddos"
PROG="/usr/local/ddos/ddos.sh"
IGNORE_IP_LIST="/usr/local/ddos/ignore.ip.list"
CRON="/etc/cron.d/ddos"

# Frequency in minutes for running the script
# Caution: Every time this setting is changed, run script with --cron
# option so that the new frequency takes effect
FREQ=1

# How many connections define a bad IP? Indicate that below.
NO_OF_CONNECTIONS=150

# APF_BAN=1 (Make sure your APF version is atleast 0.96)
# APF_BAN=0 (Uses iptables for banning ips instead of APF)
APF_BAN=0

# KILL=0 (Bad IPs are'nt banned, good for interactive execution of script)
# KILL=1 (Recommended setting)
KILL=1

# An email is sent to the following address when an IP is banned.
# Blank would suppress sending of mails
EMAIL_TO="root"

# Number of seconds the banned ip should remain in blacklist.
BAN_PERIOD=600

# Enable/disable IPv6 support
# Set to 1 to enable IPv6 support, 0 to disable
IPV6=0

# Enable/disable logging
# Set to 1 to enable logging, 0 to disable
LOGGING=1

# Location of log file
LOG_FILE="/var/log/ddos/ddos.log"

# Ports to monitor (space separated)
# Leave empty to monitor all ports
PORTS=""

# Whitelist interfaces (space separated)
# Leave empty to monitor all interfaces
WHITELIST_INTERFACES="lo"

# Detects only connections in state "ESTABLISHED"
# Set to 1 to enable, 0 to disable
ONLY_ESTABLISHED=1
EOF
}

# Function to create ignore IP list
create_ignore_ip_list() {
    print_status "Creating ignore IP list..."
    
    cat > "$INSTALL_DIR/ignore.ip.list" << 'EOF'
# DDOS Deflate Ignore IP List
# Add IP addresses that should never be blocked

# Localhost
127.0.0.1
::1

# Private networks
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16

# Add your trusted IPs below this line
# Example:
# 192.168.1.100
# 203.0.113.50
EOF

    print_success "Ignore IP list created"
}

# Function to set permissions
set_permissions() {
    print_status "Setting permissions..."
    
    chmod 0755 "$INSTALL_DIR/ddos.sh"
    chmod 0644 "$INSTALL_DIR/ddos.conf"
    chmod 0644 "$INSTALL_DIR/ignore.ip.list"
    chmod 0755 "$LOG_DIR"
    
    # Create symlinks for easy access
    ln -sf "$INSTALL_DIR/ddos.sh" /usr/local/sbin/ddos
    ln -sf "$INSTALL_DIR/ddos.sh" /usr/local/sbin/ddos-deflate
    
    print_success "Permissions set"
}

# Function to setup cron job
setup_cron_job() {
    print_status "Setting up cron job..."
    
    # Method 1: Use /etc/cron.d (preferred)
    if [ -d /etc/cron.d ]; then
        echo "$CRON_JOB" > /etc/cron.d/ddos
        chmod 0644 /etc/cron.d/ddos
        print_success "Cron job created in /etc/cron.d/ddos"
    else
        # Method 2: Use crontab
        (crontab -l 2>/dev/null | grep -v 'ddos.sh'; echo "*/1 * * * * /usr/local/ddos/ddos.sh --cron > /dev/null 2>&1") | crontab -
        print_success "Cron job added to crontab"
    fi
}

# Function to test installation
test_installation() {
    print_status "Testing installation..."
    
    # Test if script runs without errors
    if "$INSTALL_DIR/ddos.sh" --cron > /dev/null 2>&1; then
        print_success "Installation test passed"
        return 0
    else
        print_warning "Installation test had some issues, but installation completed"
        return 1
    fi
}

# Function to show installation summary
show_summary() {
    echo ""
    echo -e "${green}=========================================${nc}"
    echo -e "${green}    DDOS DEFLATE INSTALLATION COMPLETE  ${nc}"
    echo -e "${green}=========================================${nc}"
    echo ""
    echo -e "${blue}Installation Details:${nc}"
    echo -e "  Version       : ${yellow}DDOS Deflate (Latest)${nc}"
    echo -e "  Install Dir   : ${yellow}$INSTALL_DIR${nc}"
    echo -e "  Log Directory : ${yellow}$LOG_DIR${nc}"
    echo -e "  Cron Schedule : ${yellow}Every minute${nc}"
    echo ""
    echo -e "${blue}Usage Commands:${nc}"
    echo -e "  Check status  : ${green}ddos --status${nc}"
    echo -e "  View connections: ${green}ddos --view${nc}"
    echo -e "  Unblock IP    : ${green}ddos --unblock IP_ADDRESS${nc}"
    echo -e "  Start manually: ${green}ddos --start${nc}"
    echo ""
    echo -e "${blue}Configuration Files:${nc}"
    echo -e "  Main config   : ${yellow}$INSTALL_DIR/ddos.conf${nc}"
    echo -e "  Ignore IP list: ${yellow}$INSTALL_DIR/ignore.ip.list${nc}"
    echo ""
    echo -e "${green}DDOS Deflate is now active and monitoring connections!${nc}"
    echo ""
}

# Function to setup log rotation
setup_log_rotation() {
    if [ -d /etc/logrotate.d ]; then
        print_status "Setting up log rotation..."
        
        cat > /etc/logrotate.d/ddos << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF
        print_success "Log rotation configured"
    fi
}

# Main installation function
install_ddos_deflate() {
    print_status "Starting DDOS Deflate auto-installation..."
    
    # Check root
    check_root
    
    # Install dependencies
    install_dependencies
    
    # Clean previous installation
    clean_previous_installation
    
    # Create directories
    create_directories
    
    # Download files
    if ! download_ddos_deflate; then
        print_error "Download failed. Installation aborted."
        exit 1
    fi
    
    # Create ignore IP list
    create_ignore_ip_list
    
    # Set permissions
    set_permissions
    
    # Setup cron job
    setup_cron_job
    
    # Setup log rotation
    setup_log_rotation
    
    # Test installation
    test_installation
    
    # Show summary
    show_summary
    
    # Log installation
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DDOS Deflate auto-installed" >> "$LOG_DIR/install.log"
}

# Auto-detect if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed, run installation
    install_ddos_deflate
fi
