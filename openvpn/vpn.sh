#!/bin/bash
# ==========================================
# Setup openvpn
# ==========================================

# initialisasi var
export DEBIAN_FRONTEND=noninteractive
OS=`uname -m`;
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
IFACE=$(ip -o $IFACE -4 route show to default | awk '{print $5}');

# Install OpenVPN dan Easy-RSA
apt install openvpn easy-rsa unzip -y
apt install openssl iptables netfilter-persistent iptables-persistent -y
mkdir -p /etc/openvpn/server/easy-rsa/
cd /etc/openvpn/
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/vpn.zip
unzip vpn.zip
rm -f vpn.zip
chown -R root:root /etc/openvpn/server/easy-rsa/

cd
mkdir -p /usr/lib/openvpn/
cp /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so /usr/lib/openvpn/openvpn-plugin-auth-pam.so

# nano /etc/default/openvpn
sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn

# restart openvpn
systemctl enable --now openvpn-server@server-tcp
systemctl enable --now openvpn-server@server-udp
/etc/init.d/openvpn restart

# aktifkan ip4 forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

# Buat config client TCP 1194
cat > /etc/openvpn/tcp.ovpn <<EOF
client
dev tun
proto tcp
remote $MYIP 1194
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
EOF

# Buat config client UDP 2200
cat > /etc/openvpn/udp.ovpn <<EOF
client
dev tun
proto udp
remote $MYIP 2200
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
EOF

# Buat config client SSL 999
cat > /etc/openvpn/ssl.ovpn <<EOF
client
dev tun
proto tcp
remote $MYIP 999
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
EOF

cd
# TCP 1194
echo '<ca>' >> /etc/openvpn/tcp.ovpn
cat /etc/openvpn/server/ca.crt >> /etc/openvpn/tcp.ovpn
echo '</ca>' >> /etc/openvpn/tcp.ovpn

# ( TCP 1194 )
cp /etc/openvpn/tcp.ovpn /home/vps/public_html/tcp.ovpn

# UDP 2200
echo '<ca>' >> /etc/openvpn/udp.ovpn
cat /etc/openvpn/server/ca.crt >> /etc/openvpn/udp.ovpn
echo '</ca>' >> /etc/openvpn/udp.ovpn

# ( UDP 2200 )
cp /etc/openvpn/udp.ovpn /home/vps/public_html/udp.ovpn

# SSL 999
echo '<ca>' >> /etc/openvpn/ssl.ovpn
cat /etc/openvpn/server/ca.crt >> /etc/openvpn/ssl.ovpn
echo '</ca>' >> /etc/openvpn/ssl.ovpn

# ( SSL 999 )
cp /etc/openvpn/ssl.ovpn /home/vps/public_html/ssl.ovpn

iptables -C INPUT -p tcp --dport 1194 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 1194 -j ACCEPT
iptables -C INPUT -p udp --dport 2200 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p udp --dport 2200 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.6.0.0/24 -o $IFACE -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING -s 10.6.0.0/24 -o $IFACE -j MASQUERADE
iptables -t nat -C POSTROUTING -s 10.7.0.0/24 -o $IFACE -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING -s 10.7.0.0/24 -o $IFACE -j MASQUERADE
iptables-save > /etc/iptables.up.rules
chmod +x /etc/iptables.up.rules

iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload

# Restart service openvpn
systemctl enable openvpn
systemctl start openvpn

