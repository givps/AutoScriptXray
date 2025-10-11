#!/bin/bash
# =========================================
# VPN-safe Cloudflare DoH setup on VPS
# Install : wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/dns/insshws.sh && chmod +x dnsleak.sh && ./dnsleak.sh
# =========================================
set -euo pipefail

# ----------------------
# Colors
# ----------------------
green='\e[0;32m'; blue='\e[1;34m'; red='\e[1;31m'; nc='\e[0m'

# ----------------------
# Install cloudflared if missing
# ----------------------
if ! command -v cloudflared >/dev/null 2>&1; then
    echo -e "${blue}Installing cloudflared...${nc}"
    wget -q -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x /usr/local/bin/cloudflared
fi

# ----------------------
# Create systemd service
# ----------------------
echo -e "${blue}Creating cloudflared service...${nc}"
cat >/etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare DNS over HTTPS (DoH) Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared proxy-dns --address 127.0.0.1 --port 5353 --upstream https://1.1.1.1/dns-query --upstream https://9.9.9.9/dns-query --upstream https://dns.google/dns-query
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

# ----------------------
# Apply iptables/ip6tables redirect DNS -> 127.0.0.1:5353
# ----------------------
echo -e "${blue}Applying firewall rules for DNS...${nc}"

# IPv4
iptables -t nat -C OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -C OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353

# IPv6
ip6tables -t nat -C OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
    ip6tables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
ip6tables -t nat -C OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
    ip6tables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353

# ----------------------
# Block any DNS query outside DoH proxy (VPN-safe)
# ----------------------
# IPv4
iptables -t filter -A OUTPUT -p udp --dport 53 ! -d 127.0.0.1 -j REJECT
iptables -t filter -A OUTPUT -p tcp --dport 53 ! -d 127.0.0.1 -j REJECT
# IPv6
ip6tables -t filter -A OUTPUT -p udp --dport 53 ! -d ::1 -j REJECT
ip6tables -t filter -A OUTPUT -p tcp --dport 53 ! -d ::1 -j REJECT

# ----------------------
# Save firewall rules
# ----------------------
echo -e "${blue}Saving iptables rules...${nc}"
apt install -y iptables-persistent
netfilter-persistent save

# ----------------------
# Force resolver to local DoH
# ----------------------
echo -e "${blue}Setting local resolver...${nc}"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo "nameserver 127.0.0.1" > /etc/resolv.conf
chattr +i /etc/resolv.conf

# ----------------------
# Test
# ----------------------
echo -e "${green}Testing DNS via DoH...${nc}"
dig @127.0.0.1 -p 5353 github.com

echo -e "${green}✅ VPN-safe Cloudflared DoH setup completed.${nc}"