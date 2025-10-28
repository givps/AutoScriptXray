#!/bin/bash
# =========================================
# SETUP TOR + STUNNEL + SELECTIVE PORT 777
# =========================================

set -e

echo "=== Installing dependencies ==="
apt update
apt install -y tor stunnel4 iptables-persistent

echo "=== Configuring Tor ==="
cat > /etc/tor/torrc <<'EOF'
Log notice file /var/log/tor/notices.log
SOCKSPort 127.0.0.1:9050
TransPort 127.0.0.1:9040
DNSPort 127.0.0.1:5353
AvoidDiskWrites 1
RunAsDaemon 1
ControlPort 9051
CookieAuthentication 1
EOF

systemctl enable tor
systemctl restart tor

echo "=== Configuring Stunnel ==="
cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

# SSH over SSL
[ssh-ssl]
accept = 222
connect = 127.0.0.1:22

# Dropbear over SSL
[dropbear-ssl]
accept = 444
connect = 127.0.0.1:110

# Tor selective port
[tor-ssl]
accept = 0.0.0.0:777
connect = 127.0.0.1:2222
EOF

systemctl enable stunnel4
systemctl restart stunnel4

echo "=== Configuring iptables selective Tor routing ==="
# Create TOR chain if not exists
iptables -t nat -L TOR &>/dev/null || iptables -t nat -N TOR

# Get debian-tor UID (to prevent redirecting Tor itself)
TOR_UID=$(id -u debian-tor 2>/dev/null || echo 0)

# TOR chain rules
iptables -t nat -C TOR -m owner --uid-owner $TOR_UID -j RETURN 2>/dev/null || \
    iptables -t nat -A TOR -m owner --uid-owner $TOR_UID -j RETURN
iptables -t nat -C TOR -d 127.0.0.0/8 -j RETURN 2>/dev/null || \
    iptables -t nat -A TOR -d 127.0.0.0/8 -j RETURN
iptables -t nat -C TOR -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
    iptables -t nat -A TOR -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -C TOR -p tcp --dport 777 -j REDIRECT --to-ports 9040 2>/dev/null || \
    iptables -t nat -A TOR -p tcp --dport 777 -j REDIRECT --to-ports 9040

# Apply TOR chain to OUTPUT
iptables -t nat -C OUTPUT -p tcp -j TOR 2>/dev/null || \
    iptables -t nat -I OUTPUT -p tcp -j TOR

# Save iptables persistently
netfilter-persistent save

echo "=== Setup complete! ==="
echo "Tor TransPort: 127.0.0.1:9040"
echo "Tor DNSPort:   127.0.0.1:5353"
echo "Stunnel port 777 redirected to Tor"
echo "SSH over SSL: 222, Dropbear over SSL: 444"

