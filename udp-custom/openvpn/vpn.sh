#!/bin/bash
#

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
# Generate client configs with embedded CA + login prompt
CA_CONTENT=$(cat /etc/openvpn/server/ca.crt)

make_ovpn() {
  local NAME=$1
  local PROTO=$2
  local PORT=$3
  local EXTRA=$4

  cat > /etc/openvpn/${NAME}.ovpn <<-EOF
setenv FRIENDLY_NAME "${NAME^^}"
client
dev tun
proto $PROTO
remote $DOMAIN $PORT
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
$EXTRA
<ca>
$CA_CONTENT
</ca>
EOF

  sed -i $MYIP2 /etc/openvpn/${NAME}.ovpn
  cp /etc/openvpn/${NAME}.ovpn /home/vps/public_html/${NAME}.ovpn
}

# TCP 1194
make_ovpn "client-tcp-1194" "tcp" "1194" "http-proxy xxxxxxxxx 8000"

# UDP 2200
make_ovpn "client-udp-2200" "udp" "2200"

# SSL (TCP 443)
make_ovpn "client-tcp-ssl" "tcp" "443"

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
