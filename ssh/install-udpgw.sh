#!/bin/bash
# Quick BadVPN UDPGW Installer for VPS Client - FIXED COMPILATION

echo "Installing BadVPN UDPGW for VPS..."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo"
    exit 1
fi

# Detect OS and install dependencies
if [ -f /etc/debian_version ]; then
    echo "Detected Debian/Ubuntu system"
    apt-get update
    apt-get install -y wget build-essential cmake screen
elif [ -f /etc/redhat-release ]; then
    echo "Detected CentOS/RHEL system"
    yum update -y
    yum install -y wget gcc gcc-c++ make cmake screen
else
    echo "Unsupported OS. Trying to continue..."
fi

# Clean up previous installations
echo "Cleaning up previous installations..."
cd /tmp
rm -rf badvpn-1.999.130 1.999.130.tar.gz
pkill -f badvpn-udpgw
pkill -f "screen.*udpgw"

# Download BadVPN
echo "Downloading BadVPN..."
wget -q https://github.com/ambrop72/badvpn/archive/1.999.130.tar.gz

if [ ! -f "1.999.130.tar.gz" ]; then
    echo "Failed to download BadVPN. Using alternative source..."
    wget -q https://codeload.github.com/ambrop72/badvpn/tar.gz/1.999.130 -O 1.999.130.tar.gz
fi

# Extract and compile
echo "Extracting BadVPN..."
tar xzf 1.999.130.tar.gz
cd badvpn-1.999.130

# Remove existing build directory if exists
rm -rf build

echo "Compiling BadVPN..."
mkdir build
cd build

# Compile with better error handling
echo "Running CMake..."
if ! cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 .. ; then
    echo "CMake failed. Checking dependencies..."
    # Install missing dependencies
    apt-get install -y libnspr4-dev libnss3-dev || yum install -y nss-devel nspr-devel
    echo "Retrying CMake..."
    cmake -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 ..
fi

echo "Running Make..."
if ! make ; then
    echo "Compilation failed. Trying alternative approach..."
    cd ..
    rm -rf build
    mkdir build
    cd build
    cmake ..
    make
fi

# Check if compilation succeeded
if [ ! -f "udpgw/badvpn-udpgw" ]; then
    echo "❌ Compilation failed. BadVPN binary not created."
    echo "Please check the errors above and install required dependencies manually."
    exit 1
fi

# Install binary
echo "Installing BadVPN UDPGW..."
cp udpgw/badvpn-udpgw /usr/local/bin/
chmod +x /usr/local/bin/badvpn-udpgw

# Create management scripts
create_management_scripts() {
    # udpgw-start
    cat > /usr/local/bin/udpgw-start << 'EOF'
#!/bin/bash
PORTS="7100 7200 7300 7400 7500 7600 7700 7800 7900"
MAX_CLIENTS=1000

echo "Starting BadVPN UDPGW..."
pkill -f badvpn-udpgw
sleep 2

for port in $PORTS; do
    echo "Starting port $port"
    screen -dmS udpgw-$port /usr/local/bin/badvpn-udpgw --listen-addr 0.0.0.0:$port --max-clients $MAX_CLIENTS
    sleep 1
done

echo "BadVPN UDPGW started on ports: $PORTS"
EOF

    # udpgw-stop
    cat > /usr/local/bin/udpgw-stop << 'EOF'
#!/bin/bash
echo "Stopping BadVPN UDPGW..."
pkill -f badvpn-udpgw
pkill -f "screen.*udpgw"
sleep 2
echo "BadVPN UDPGW stopped"
EOF

    # udpgw-status
    cat > /usr/local/bin/udpgw-status << 'EOF'
#!/bin/bash
PORTS="7100 7200 7300 7400 7500 7600 7700 7800 7900"
echo "BadVPN UDPGW Status:"
echo "==================="

for port in $PORTS; do
    if pgrep -f "badvpn-udpgw.*$port" > /dev/null; then
        echo "Port $port: ✓ RUNNING"
    else
        echo "Port $port: ✗ STOPPED"
    fi
done
EOF

    chmod +x /usr/local/bin/udpgw-start
    chmod +x /usr/local/bin/udpgw-stop
    chmod +x /usr/local/bin/udpgw-status
    
    echo "Management scripts created"
}

create_management_scripts

# Start BadVPN UDPGW
echo "Starting BadVPN UDPGW services..."
/usr/local/bin/udpgw-start

# Create systemd service
cat > /etc/systemd/system/badvpn-udpgw.service << EOF
[Unit]
Description=BadVPN UDP Gateway Service
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/udpgw-start
ExecStop=/usr/local/bin/udpgw-stop
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable badvpn-udpgw.service

# Allow BadVpn
iptables -L INPUT -n --line-numbers
iptables -C INPUT -p udp --dport 7100 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7100 -j ACCEPT
iptables -C INPUT -p udp --dport 7200 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7200 -j ACCEPT
iptables -C INPUT -p udp --dport 7300 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7300 -j ACCEPT
iptables -C INPUT -p udp --dport 7400 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7400 -j ACCEPT
iptables -C INPUT -p udp --dport 7500 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7500 -j ACCEPT
iptables -C INPUT -p udp --dport 7600 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7600 -j ACCEPT
iptables -C INPUT -p udp --dport 7700 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7700 -j ACCEPT
iptables -C INPUT -p udp --dport 7800 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7800 -j ACCEPT
iptables -C INPUT -p udp --dport 7900 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 7900 -j ACCEPT

netfilter-persistent save
netfilter-persistent reload
echo ""
echo "========================================"
echo "✅ BadVPN UDPGW Installation Complete!"
echo "========================================"
echo ""
echo "Usage:"
echo "  udpgw-start     - Start service"
echo "  udpgw-stop      - Stop service" 
echo "  udpgw-status    - Check status"
echo ""
echo "Ports: 7100-7900"
