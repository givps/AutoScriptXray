#!/bin/bash
# =========================================
# SETUP WIREGUARD VPN
# =========================================

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

# Detect default network interface (e.g. eth0, ens3, ens160, enp1s0, etc.)
interface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')

# Fallback method if detection fails
if [ -z "$interface" ]; then
  interface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v -E "lo|wg|docker" | head -n 1)
fi

# Final validation
if [ -z "$interface" ]; then
  echo "❌ Failed to detect default interface. Check your network connection!"
  exit 1
else
  echo "✅ Default interface detected: $interface"
fi

# Check if subnet 10.88.88.0/22 is already in use
if ip addr | grep -q "10\.88\.88\."; then
  echo "Subnet 10.88.88.0/22 is already in use! Please choose a different subnet."
  exit 1
fi

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.88.88.1/22
ListenPort = 8888
PrivateKey = $privkey
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; \
         iptables -A FORWARD -o wg0 -j ACCEPT; \
         iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -D FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE
SaveConfig = true
EOF

chmod 600 /etc/wireguard/wg0.conf

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/30-wireguard.conf
sysctl --system >/dev/null 2>&1

systemctl enable wg-quick@wg0.service >/dev/null 2>&1
systemctl restart wg-quick@wg0.service

echo "Public Key : $pubkey"
echo "Listen Port: 8888"
echo "Interface  : $interface"

cd /usr/bin
wget -O m-wg "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/m-wg.sh"
wget -O wg-add "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-add.sh"
wget -O wg-del "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-del.sh"
wget -O wg-renew "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-renew.sh"
wget -O wg-show "https://raw.githubusercontent.com/givps/AutoScriptXray/master/wireguard/wg-show.sh"

chmod +x m-wg
chmod +x wg-add
chmod +x wg-del
chmod +x wg-renew
chmod +x wg-show
