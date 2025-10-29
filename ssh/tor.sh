#!/bin/bash
# =====================================
# SETUP TOR
# =====================================
apt install -y tor

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

# disable auto start after reboot
systemctl disable tor
systemctl stop tor
# enable auto start after reboot
#systemctl restart tor
#systemctl enable tor

#iptables -t nat -L TOR &>/dev/null || iptables -t nat -N TOR
#TOR_UID=$(id -u debian-tor 2>/dev/null || echo 0)
#iptables -t nat -C TOR -m owner --uid-owner $TOR_UID -j RETURN 2>/dev/null || \
#iptables -t nat -A TOR -m owner --uid-owner $TOR_UID -j RETURN
#iptables -t nat -C TOR -d 127.0.0.0/8 -j RETURN 2>/dev/null || \
#iptables -t nat -A TOR -d 127.0.0.0/8 -j RETURN
#iptables -t nat -C TOR -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
#iptables -t nat -A TOR -p udp --dport 53 -j REDIRECT --to-ports 5353
#iptables -t nat -C TOR -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || \
#iptables -t nat -A TOR -p tcp -j REDIRECT --to-ports 9040
#iptables -t nat -C OUTPUT -p tcp -j TOR 2>/dev/null || \
#iptables -t nat -I OUTPUT -p tcp -j TOR

# Simpan rules
#netfilter-persistent save
#netfilter-persistent reload

