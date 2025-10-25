#!/bin/bash
# =========================================
# SETUP WIREGUARD VPN
# =========================================

rm -f /usr/bin/m-wg
rm -f /usr/bin/wg-add
rm -f /usr/bin/wg-del
rm -f /usr/bin/wg-renew
rm -f /usr/bin/wg-show

systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0
apt purge -y wireguard
rm -rf /etc/wireguard

# Update system and install dependencies
apt update -qq
apt install -y wireguard qrencode resolvconf iproute2 iptables -qq

# Create configuration directory
mkdir -p /etc/wireguard

# Generate or load existing private & public keys
if [ ! -s /etc/wireguard/private.key ]; then
  umask 077
  privkey=$(wg genkey)
  pubkey=$(echo "$privkey" | wg pubkey)
  echo "$privkey" > /etc/wireguard/private.key
  echo "$pubkey" > /etc/wireguard/public.key
else
  privkey=$(< /etc/wireguard/private.key)
  pubkey=$(< /etc/wireguard/public.key)
fi

# Detect default interface
interface=$(ip route get 1 | awk '{print $5; exit}')
if [ -z "$interface" ]; then
    echo "❌ Failed to detect default network interface!"
    exit 1
fi
echo "✅ Default interface detected: $interface"

# Create WireGuard config
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.88.88.1/22
ListenPort = 8888
PrivateKey = $privkey
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE
SaveConfig = true
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable IPv4 forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/30-wireguard.conf
sysctl --system >/dev/null 2>&1

# Enable and start WireGuard service
systemctl enable wg-quick@wg0.service >/dev/null 2>&1
if systemctl restart wg-quick@wg0.service; then
    echo "✅ WireGuard service started successfully!"
else
    echo "❌ Failed to start WireGuard service. Check 'systemctl status wg-quick@wg0'"
    exit 1
fi

# Display server info
echo "Public Key : $pubkey"
echo "Listen Port: 8888"
echo "Interface  : $interface"

# Download management scripts
cd /usr/bin || exit
wget -q -O m-wg "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/m-wg.sh"
wget -q -O wg-add "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-add.sh"
wget -q -O wg-del "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-del.sh"
wget -q -O wg-renew "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-renew.sh"
wget -q -O wg-show "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-show.sh"

chmod +x m-wg wg-add wg-del wg-renew wg-show

echo "✅ WireGuard setup complete!"
