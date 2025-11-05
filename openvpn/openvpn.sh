#!/bin/bash
# =========================================
# setup openvpn
# =========================================

# initialisasi var
export DEBIAN_FRONTEND=noninteractive
OS=`uname -m`;
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me);
sudo rm /etc/resolv.conf
sudo ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
sudo apt update
sudo apt install resolvconf -y
sudo systemctl enable --now resolvconf.service

cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

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

case $script_type in
  up)
    # Set DNS global (Cloudflare + Google)
    cat <<EOT > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOT
    ;;
  down)
    # jangan restore supaya klien lain tidak terganggu
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

IFACE=$(ip -o -4 route show to default | awk '{print $5}')

if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
    echo 1 > /proc/sys/net/ipv4/ip_forward
fi

for SUBNET in 10.6.0.0/24 10.7.0.0/24 10.8.0.0/24; do
    iptables -t nat -C POSTROUTING -s $SUBNET -o $IFACE -j MASQUERADE 2>/dev/null || \
    iptables -t nat -I POSTROUTING -s $SUBNET -o $IFACE -j MASQUERADE
done

iptables -C FORWARD -i tun0 -o $IFACE -j ACCEPT 2>/dev/null || \
iptables -I FORWARD -i tun0 -o $IFACE -j ACCEPT
iptables -C FORWARD -i $IFACE -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD -i $IFACE -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -C FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

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
