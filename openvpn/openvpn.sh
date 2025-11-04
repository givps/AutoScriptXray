#!/bin/bash
# =========================================
# setup openvpn
# =========================================

# initialisasi var
export DEBIAN_FRONTEND=noninteractive
OS=`uname -m`;
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me);
rm -rf /etc/openvpn/
rm -rf /usr/share/nginx/html/openvpn/
mkdir -p /usr/share/nginx/html/openvpn/
wget -q -O /usr/share/nginx/html/openvpn/index.html "https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/index"
nginx -t && systemctl reload nginx
# Install OpenVPN dan Easy-RSA
apt install openvpn easy-rsa unzip -y
apt install openssl iptables iptables-persistent -y
mkdir -p /etc/openvpn/
cd /etc/openvpn/
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/server.zip
unzip server.zip
rm -f server.zip
chown -R root:root /etc/openvpn/

cd
mkdir -p /usr/lib/openvpn/
cp /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so /usr/lib/openvpn/openvpn-plugin-auth-pam.so

# /etc/default/openvpn
sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn

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

auth-user-pass
auth SHA256
cipher AES-256-GCM
verb 3

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

auth-user-pass
auth SHA256
cipher AES-256-GCM
verb 3

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

# OpenVPN TCP 1195
iptables -C INPUT -p tcp --dport 1195 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1195 -j ACCEPT

# OpenVPN TCP 1196
iptables -C INPUT -p tcp --dport 1196 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1196 -j ACCEPT

# OpenVPN UDP 51825
iptables -C INPUT -p udp --dport 51825 -m limit --limit 30/sec --limit-burst 50 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p udp --dport 51825 -m limit --limit 30/sec --limit-burst 50 -j ACCEPT

netfilter-persistent save
netfilter-persistent reload

# enable openvpnsystemctl daemon-reload
systemctl start openvpn-server@server-tcp
systemctl start openvpn-server@server-udp
systemctl start openvpn-server@server-ssl
systemctl start openvpn
systemctl enable openvpn-server@server-tcp
systemctl enable openvpn-server@server-udp
systemctl enable openvpn-server@server-ssl
systemctl enable openvpn
systemctl restart openvpn-server@server-tcp
systemctl restart openvpn-server@server-udp
systemctl restart openvpn-server@server-ssl
systemctl restart openvpn
