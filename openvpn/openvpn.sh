#!/bin/bash
# =========================================
# setup openvpn
# =========================================

# initialisasi var
export DEBIAN_FRONTEND=noninteractive
OS=`uname -m`;
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me);
sudo bash -c 'for ns in 1.1.1.1 8.8.8.8; do grep -q "^nameserver $ns" /etc/resolv.conf || echo "nameserver $ns" >> /etc/resolv.conf; done'
sudo apt update
sudo apt install resolvconf -y
sudo ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf
sudo systemctl enable --now resolvconf
sudo resolvconf -u

rm -rf /etc/openvpn/
rm -f /usr/share/nginx/html/openvpn/*.ovpn
mkdir -p /usr/share/nginx/html/openvpn/
wget -q -O /usr/share/nginx/html/openvpn/index.html "https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/index"
systemctl daemon-reload
systemctl reload nginx
# Install OpenVPN dan Easy-RSA
apt install openvpn easy-rsa unzip -y
apt install openssl iptables iptables-persistent netfilter-persistent -y
mkdir -p /etc/openvpn/
cd /etc/openvpn/
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/server.zip
unzip server.zip
rm -f server.zip
chown -R root:root /etc/openvpn/

sudo tee /etc/openvpn/update-resolv-conf.sh > /dev/null <<'EOF'
#!/bin/bash
# Update DNS untuk OpenVPN client (tidak ganggu host)

DNS1="1.1.1.1"
DNS2="8.8.8.8"

case "$script_type" in
  up|down)
    if [ -n "$dev" ]; then
        # gunakan resolvconf jika ada
        if command -v resolvconf >/dev/null 2>&1; then
            printf "nameserver %s\nnameserver %s\n" "$DNS1" "$DNS2" | resolvconf -a "$dev"
            resolvconf -u
        else
            # fallback: tulis ke /etc/openvpn/resolv.conf (khusus client)
            mkdir -p /etc/openvpn
            echo -e "nameserver $DNS1\nnameserver $DNS2" > /etc/openvpn/resolv.conf
        fi
    fi
    ;;
esac
EOF

# Jadikan executable
sudo chmod +x /etc/openvpn/update-resolv-conf.sh

cd
mkdir -p /usr/lib/openvpn/
cp /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so /usr/lib/openvpn/openvpn-plugin-auth-pam.so

# /etc/default/openvpn
sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn

# enable openvpn
systemctl enable --now openvpn-server@server-tcp
systemctl enable --now openvpn-server@server-udp
systemctl enable --now openvpn-server@server-ssl
systemctl enable --now openvpn

# Buat config client TCP 1195
cat > /etc/openvpn/tcp.ovpn <<EOF
client
dev tun
proto tcp
remote $MYIP 1195
resolv-retry infinite
nobind
persist-key
persist-tun
tcp-nodelay
explicit-exit-notify 1

auth-user-pass
auth SHA256
cipher AES-256-GCM
remote-cert-tls server
tls-version-min 1.2
verb 3
keepalive 10 120
redirect-gateway def1

script-security 2
up /etc/openvpn/update-resolv-conf.sh
down /etc/openvpn/update-resolv-conf.sh

<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/server/client.crt)
</cert>

<key>
$(cat /etc/openvpn/server/client.key)
</key>

<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
key-direction 1
EOF

# Buat config client UDP 51825
cat > /etc/openvpn/udp.ovpn <<EOF
client
dev tun
proto udp
remote $MYIP 51825
resolv-retry infinite
nobind
persist-key
persist-tun

auth-user-pass
auth SHA256
cipher AES-256-GCM
verb 3
explicit-exit-notify 1
keepalive 10 120
redirect-gateway def1

script-security 2
up /etc/openvpn/update-resolv-conf.sh
down /etc/openvpn/update-resolv-conf.sh

<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/server/client.crt)
</cert>

<key>
$(cat /etc/openvpn/server/client.key)
</key>

<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
key-direction 1
EOF

# Buat config client SSL 443
cat > /etc/openvpn/ssl.ovpn <<EOF
client
dev tun
proto tcp
remote $MYIP 443
resolv-retry infinite
nobind
persist-key
persist-tun
tcp-nodelay
explicit-exit-notify 1

auth-user-pass
auth SHA256
cipher AES-256-GCM
remote-cert-tls server
tls-version-min 1.2
verb 3
keepalive 10 120
redirect-gateway def1

script-security 2
up /etc/openvpn/update-resolv-conf.sh
down /etc/openvpn/update-resolv-conf.sh

<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/server/client.crt)
</cert>

<key>
$(cat /etc/openvpn/server/client.key)
</key>

<tls-auth>
$(cat /etc/openvpn/server/ta.key)
</tls-auth>
key-direction 1
EOF

# Copy config OpenVPN client ke home directory root agar mudah didownload ( TCP 1195 )
cp /etc/openvpn/tcp.ovpn /usr/share/nginx/html/openvpn/tcp.ovpn
# Copy config OpenVPN client ke home directory root agar mudah didownload ( UDP 51825 )
cp /etc/openvpn/udp.ovpn /usr/share/nginx/html/openvpn/udp.ovpn
# Copy config OpenVPN client ke home directory root agar mudah didownload ( SSL 443 )
cp /etc/openvpn/ssl.ovpn /usr/share/nginx/html/openvpn/ssl.ovpn
# Buat direktori sementara untuk ZIP
mkdir -p /tmp/ovpn
# Salin semua konfigurasi ke direktori sementara
cp /etc/openvpn/tcp.ovpn /tmp/ovpn/
cp /etc/openvpn/udp.ovpn /tmp/ovpn/
cp /etc/openvpn/ssl.ovpn /tmp/ovpn/
# Buat file ZIP berisi semua konfigurasi
cd /tmp
zip ovpn.zip -r ovpn
# Pindahkan ZIP ke direktori public_html agar bisa diunduh
mv ovpn.zip /usr/share/nginx/html/openvpn/
# Hapus direktori sementara
rm -rf /tmp/ovpn
cd

sudo tee /usr/local/bin/install-fix-iptables.sh > /dev/null <<'EOF'
#!/bin/bash
set -e
echo "[INFO] Creating fix-iptables.sh..."

sudo tee /usr/local/bin/fix-iptables.sh > /dev/null <<'EOSH'
#!/bin/bash
GREEN="\e[32m"
RESET="\e[0m"

# Detect default network interface
IFACE=$(ip -o -4 route show to default | awk '{print $5}')

# Enable IP forwarding
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo -e "${GREEN}[OK]${RESET} IP forwarding enabled"
fi

# Apply NAT for OpenVPN subnets
for SUBNET in 10.6.0.0/24 10.7.0.0/24 10.8.0.0/24; do
    iptables -t nat -C POSTROUTING -s $SUBNET -o $IFACE -j MASQUERADE 2>/dev/null || \
    iptables -t nat -I POSTROUTING -s $SUBNET -o $IFACE -j MASQUERADE
    echo -e "${GREEN}[OK]${RESET} NAT applied for subnet $SUBNET via $IFACE"
done

# Forward traffic between tun interfaces and default interface
for DEV in $(ip -o link show | awk -F': ' '{print $2}' | grep '^tun'); do
    iptables -C FORWARD -i $DEV -o $IFACE -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD -i $DEV -o $IFACE -j ACCEPT
    iptables -C FORWARD -i $IFACE -o $DEV -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD -i $IFACE -o $DEV -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo -e "${GREEN}[OK]${RESET} Forwarding rule applied for $DEV ↔ $IFACE"
done

# Ensure established connections are forwarded
iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
echo -e "${GREEN}[OK]${RESET} Related/Established forwarding rule ensured"
EOSH

chmod +x /usr/local/bin/fix-iptables.sh

echo "[INFO] Creating systemd service fix-iptables.service..."
sudo tee /etc/systemd/system/fix-iptables.service > /dev/null <<'EOSERVICE'
[Unit]
Description=Fix OpenVPN iptables and NAT rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-iptables.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOSERVICE

echo "[INFO] Reloading systemd daemon..."
systemctl daemon-reload

echo "[INFO] Enabling and starting service..."
systemctl enable fix-iptables.service
systemctl start fix-iptables.service || true

echo
echo "✅ Installation complete! You can check status with:"
echo "   systemctl status fix-iptables"
echo "   journalctl -u fix-iptables -e"
EOF

# Run the installer
sudo chmod +x /usr/local/bin/install-fix-iptables.sh
sudo bash /usr/local/bin/install-fix-iptables.sh

# /etc/systemd/system/fix-iptables.timer
cat <<'EOF' | sudo tee /etc/systemd/system/fix-iptables.timer
[Unit]
Description=Run fix-iptables every 15 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=15min
Unit=fix-iptables.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now fix-iptables.timer

# OpenVPN TCP 1195
iptables -C INPUT -p tcp --dport 1195 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1195 -j ACCEPT

# OpenVPN TCP 1196
iptables -C INPUT -p tcp -s 127.0.0.1 --dport 1196 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp -s 127.0.0.1 --dport 1196 -j ACCEPT
iptables -A INPUT -p tcp --dport 1196 -j DROP

# OpenVPN UDP 51825
iptables -C INPUT -p udp --dport 51825 -m limit --limit 30/sec --limit-burst 50 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p udp --dport 51825 -m limit --limit 30/sec --limit-burst 50 -j ACCEPT

netfilter-persistent save
netfilter-persistent reload
