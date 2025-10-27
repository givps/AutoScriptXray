#!/bin/bash
# =========================================
# DNS SETUP slowdns Cloudflare API Token
# =========================================
apt install -y bind9 bind9utils bind9-dnsutils dnsutils
systemctl enable bind9
systemctl start bind9
# Tambah rule INPUT UDP 5300 kalau belum ada
iptables -F f2b-sshd
iptables -L INPUT -n --line-numbers
iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables -C INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 53 -j ACCEPT
iptables -C INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -C INPUT -p tcp --dport 5300 -j ACCEPT 2>/dev/null || \
iptables -I INPUT -p tcp --dport 5300 -j ACCEPT

# Tambah NAT redirect 53 -> 5300 kalau belum ada
iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || \
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
iptables -t nat -C PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || \
iptables -t nat -I PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 5300

netfilter-persistent save
# Remove old directory/file
rm -rf /root/nsdomain
rm -f nsdomain

# Get the main domain
domen=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# Domain and subdomain configuration
subsl=$(</dev/urandom tr -dc 0-9 | head -c5)
DOMAIN="ipgivpn.my.id"
SUB_DOMAIN="${domen}"
NS_DOMAIN="asxns${subsl}.ipgivpn.my.id"
echo "$NS_DOMAIN" > /root/nsdomain

# Ask for Cloudflare API Token manually (fallback to default if empty)
read -rp "Enter your Cloudflare API Token (Enter to use default): " CF_TOKEN
if [[ -z "$CF_TOKEN" ]]; then
    CF_TOKEN="XCu7wHsxlkbcU3GSPOEvl1BopubJxA9kDcr-Tkt8"
    echo "Using default API token..."
else
    echo "Using manual API token."
fi

echo "Automatically adding NS record for ${SUB_DOMAIN}..."

# Get Cloudflare Zone ID
ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" \
     -H "Authorization: Bearer ${CF_TOKEN}" \
     -H "Content-Type: application/json" | jq -r '.result[0].id')

# Check if NS record already exists
RECORD=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${NS_DOMAIN}" \
     -H "Authorization: Bearer ${CF_TOKEN}" \
     -H "Content-Type: application/json" | jq -r '.result[0].id')

# Create new NS record if not exists
if [[ "${#RECORD}" -le 10 ]]; then
     RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "Authorization: Bearer ${CF_TOKEN}" \
     -H "Content-Type: application/json" \
     --data '{"type":"NS","name":"'${NS_DOMAIN}'","content":"'${SUB_DOMAIN}'","ttl":120,"proxied":false}' | jq -r '.result.id')
fi

# Update record if already exists
RESULT=$(curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
     -H "Authorization: Bearer ${CF_TOKEN}" \
     -H "Content-Type: application/json" \
     --data '{"type":"NS","name":"'${NS_DOMAIN}'","content":"'${SUB_DOMAIN}'","ttl":120,"proxied":false}')

systemctl enable cron
systemctl restart cron

nameserver=$(cat /root/nsdomain)

#tambahan port openssh
grep -qxF "Port 2200" /etc/ssh/sshd_config || echo "Port 2200" >> /etc/ssh/sshd_config
grep -qxF "Port 2299" /etc/ssh/sshd_config || echo "Port 2299" >> /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config

systemctl enable sshd
systemctl restart sshd

#konfigurasi slowdns
rm -rf /etc/slowdns
mkdir -m 777 /etc/slowdns
wget -q -O /etc/slowdns/server.key "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.key"
wget -q -O /etc/slowdns/server.pub "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.pub"
wget -q -O /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
wget -q -O /etc/slowdns/sldns-client "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-client"

chmod +x /etc/slowdns/server.key
chmod +x /etc/slowdns/server.pub
chmod +x /etc/slowdns/sldns-server
chmod +x /etc/slowdns/sldns-client

#wget -q -O /etc/systemd/system/client-sldns.service "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/client-sldns.service"
#wget -q -O /etc/systemd/system/server-sldns.service "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server-sldns.service"

#install client-sldns.service
cat > /etc/systemd/system/client-sldns.service << END
[Unit]
Description=Client SlowDNS By SL
Documentation=https://nekopoi.care
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/etc/slowdns/sldns-client -udp 8.8.8.8:53 --pubkey-file /etc/slowdns/server.pub $nameserver 127.0.0.1:2200
Restart=on-failure

[Install]
WantedBy=multi-user.target
END

#install server-sldns.service
cat > /etc/systemd/system/server-sldns.service << END
[Unit]
Description=Server SlowDNS By SL
Documentation=https://nekopoi.care
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/etc/slowdns/sldns-server -udp :5300 -privkey-file /etc/slowdns/server.key $nameserver 127.0.0.1:2299
Restart=on-failure

[Install]
WantedBy=multi-user.target
END

#permission service slowdns
chmod +x /etc/systemd/system/client-sldns.service
chmod +x /etc/systemd/system/server-sldns.service
pkill sldns-server
pkill sldns-client

systemctl daemon-reload

systemctl enable client-sldns
systemctl enable server-sldns

systemctl start client-sldns
systemctl start server-sldns

echo -e "\e[1;32m Success.. \e[0m"
clear
echo "Success Pointing NS $nameserver With Target $domen"
