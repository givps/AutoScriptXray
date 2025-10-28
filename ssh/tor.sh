apt install -y tor stunnel4

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

systemctl restart tor
systemctl enable tor

cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

# =====================================
# SSH
# =====================================
[ssh-ssl]
accept = 222
connect = 127.0.0.1:22

# =====================================
# Dropbear
# =====================================
[dropbear-ssl]
accept = 444
connect = 127.0.0.1:110

# =====================================
# Tor
# =====================================
[tor-ssl]
accept = 0.0.0.0:777
connect = 127.0.0.1:2222
EOF

systemctl restart stunnel4
systemctl enable stunnel4

#!/bin/bash

iptables -t nat -L TOR &>/dev/null || iptables -t nat -N TOR
TOR_UID=$(id -u debian-tor 2>/dev/null || echo 0)
iptables -t nat -C TOR -m owner --uid-owner $TOR_UID -j RETURN 2>/dev/null || \
iptables -t nat -A TOR -m owner --uid-owner $TOR_UID -j RETURN
iptables -t nat -C TOR -d 127.0.0.0/8 -j RETURN 2>/dev/null || \
iptables -t nat -A TOR -d 127.0.0.0/8 -j RETURN
iptables -t nat -C TOR -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
iptables -t nat -A TOR -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -C TOR -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || \
iptables -t nat -A TOR -p tcp -j REDIRECT --to-ports 9040
iptables -t nat -C OUTPUT -p tcp -j TOR 2>/dev/null || \
iptables -t nat -I OUTPUT -p tcp -j TOR

# Simpan rules
netfilter-persistent save
netfilter-persistent reload

