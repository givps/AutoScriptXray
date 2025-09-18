#!/bin/bash
# Quick Setup | Script Setup Manager
# Edition : Stable Edition 1.1 (Fixed, English)
# Author  : givps
# The MIT License (MIT)
# (C) Copyright 2023
# =========================================

export DEBIAN_FRONTEND=noninteractive
OS=$(uname -m)
MYIP=$(wget -qO- ipv4.icanhazip.com)
MYIP2="s/xxxxxxxxx/$MYIP/g"
NIC=$(ip -o -4 route show to default | awk '{print $5}')
DOMAIN=$(cat /root/domain)

# =========================================
# Install OpenVPN and dependencies
apt install -y openvpn easy-rsa unzip openssl iptables iptables-persistent

mkdir -p /etc/openvpn/server/easy-rsa/
cd /etc/openvpn/
wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/udp-custom/openvpn/vpn.zip
unzip vpn.zip && rm -f vpn.zip
chown -R root:root /etc/openvpn/server/easy-rsa/

# PAM plugin
mkdir -p /usr/lib/openvpn/
cp /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so \
   /usr/lib/openvpn/openvpn-plugin-auth-pam.so

# Enable OpenVPN services
sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn
systemctl enable --now openvpn-server@server-tcp-1194
systemctl enable --now openvpn-server@server-udp-2200

# IPv4 forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

# =========================================
# Generate client configs

# TCP 1194
cat > /etc/openvpn/client-tcp-1194.ovpn <<-EOF
setenv FRIENDLY_NAME "OVPN TCP"
client
dev tun
proto tcp
remote $DOMAIN 1194
http-proxy xxxxxxxxx 8000
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>
EOF
sed -i $MYIP2 /etc/openvpn/client-tcp-1194.ovpn
cp /etc/openvpn/client-tcp-1194.ovpn /home/vps/public_html/

# UDP 2200
cat > /etc/openvpn/client-udp-2200.ovpn <<-EOF
setenv FRIENDLY_NAME "OVPN UDP"
client
dev tun
proto udp
remote $DOMAIN 2200
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>
EOF
sed -i $MYIP2 /etc/openvpn/client-udp-2200.ovpn
cp /etc/openvpn/client-udp-2200.ovpn /home/vps/public_html/

# SSL (TCP 443 instead of 442, adjust if needed)
cat > /etc/openvpn/client-tcp-ssl.ovpn <<-EOF
setenv FRIENDLY_NAME "OVPN SSL"
client
dev tun
proto tcp
remote $DOMAIN 443
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>
EOF
sed -i $MYIP2 /etc/openvpn/client-tcp-ssl.ovpn
cp /etc/openvpn/client-tcp-ssl.ovpn /home/vps/public_html/

# =========================================
# Firewall rules for VPN subnets
iptables -t nat -I POSTROUTING -s 10.6.0.0/24 -o $NIC -j MASQUERADE
iptables -t nat -I POSTROUTING -s 10.7.0.0/24 -o $NIC -j MASQUERADE
netfilter-persistent save
netfilter-persistent reload

# Restart OpenVPN
systemctl restart openvpn

# =========================================
# Cleanup
history -c
rm -f /root/vpn.sh
