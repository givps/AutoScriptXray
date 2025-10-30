#!/bin/bash
# =========================================
# FIXED OPENVPN SETUP SCRIPT
# =========================================

export DEBIAN_FRONTEND=noninteractive
OS=$(uname -m)
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
MYIP2="s/xxxxxxxxx/$MYIP/g"
NIC=$(ip -o -4 route show to default | awk '{print $5}')
DOMAIN=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# ---------- Install dependencies ----------
apt purge -y openvpn easy-rsa
apt autoremove -y
apt update
apt install -y openvpn easy-rsa unzip openssl iptables iptables-persistent netfilter-persistent

# ---------- Clean old config ----------
rm -rf /etc/openvpn
mkdir -p /etc/openvpn

# ---------- Download and unzip VPN config ----------
wget -O /etc/openvpn/vpn.zip https://raw.githubusercontent.com/givps/AutoScriptXray/master/openvpn/vpn.zip
unzip /etc/openvpn/vpn.zip -d /etc/openvpn/ && rm -f /etc/openvpn/vpn.zip
mv /etc/openvpn/vpn/server /etc/openvpn/
rm -rf /etc/openvpn/vpn

# ---------- Set permissions ----------
chown -R root:root /etc/openvpn/server
chmod 600 /etc/openvpn/server/*.key
chmod 644 /etc/openvpn/server/*.crt /etc/openvpn/server/*.pem
chmod +x /etc/openvpn/server/easy-rsa/easyrsa

# ---------- PAM plugin ----------
mkdir -p /usr/lib/openvpn/
cp -n /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so /usr/lib/openvpn/openvpn-plugin-auth-pam.so || true

# ---------- Enable OpenVPN services ----------
sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn
systemctl daemon-reload
systemctl enable openvpn-server@server-tcp-1194
systemctl enable openvpn-server@server-udp-1195
systemctl enable openvpn-server@server-tcp-1196

# ---------- IPv4 forwarding ----------
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sysctl -p

# ---------- Make client configs ----------
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
    mkdir -p /home/vps/public_html/
    cp /etc/openvpn/${NAME}.ovpn /home/vps/public_html/${NAME}.ovpn
}

make_ovpn "client-tcp-1194" "tcp" "1194"
make_ovpn "client-udp-1195" "udp" "1195"
make_ovpn "client-ssl-888" "tcp" "888"

# ---------- Firewall ----------
for subnet in 10.6.0.0/24 10.7.0.0/24 10.8.0.0/24; do
    iptables -t nat -C POSTROUTING -s $subnet -o $NIC -j MASQUERADE 2>/dev/null || \
    iptables -t nat -I POSTROUTING -s $subnet -o $NIC -j MASQUERADE
done

for port in 1194/tcp 1195/udp 888/tcp; do
    proto=$(echo $port | cut -d/ -f2)
    p=$(echo $port | cut -d/ -f1)
    iptables -C INPUT -p $proto --dport $p -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p $proto --dport $p -j ACCEPT
done

netfilter-persistent save
netfilter-persistent reload

cp /etc/openvpn/server/server-tcp-1194.conf /etc/openvpn/server/server-udp-1195.conf
sed -i 's/^proto tcp/proto udp/' /etc/openvpn/server/server-udp-1195.conf
sed -i 's/^port 1194/port 1195/' /etc/openvpn/server/server-udp-1195.conf

cp /etc/openvpn/server/server-tcp-1194.conf /etc/openvpn/server/server-tcp-1196.conf
sed -i 's/^port 1194/port 1196/' /etc/openvpn/server/server-tcp-1196.conf

# ---------- Restart OpenVPN ----------
systemctl daemon-reload
systemctl restart openvpn-server@server-tcp-1194
systemctl restart openvpn-server@server-udp-1195
systemctl restart openvpn-server@server-tcp-1196
systemctl enable openvpn-server@server-tcp-1194
systemctl enable openvpn-server@server-udp-1195
systemctl enable openvpn-server@server-tcp-1196

