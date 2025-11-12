#!/bin/bash
# =========================================
# install ssh tool
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
cyan='\e[1;36m'
white='\e[1;37m'
nc='\e[0m'

# Update system first
apt update -y

# Remove unused or conflicting firewall/mail services
systemctl stop ufw 2>/dev/null
systemctl disable ufw 2>/dev/null
apt-get remove --purge -y ufw firewalld exim4

# Install base system tools and network utilities
apt install -y \
  shc wget curl figlet ruby python3 make cmake \
  iptables iptables-persistent netfilter-persistent \
  coreutils rsyslog net-tools htop screen \
  zip unzip nano sed gnupg bc jq bzip2 gzip \
  apt-transport-https build-essential dirmngr \
  libxml-parser-perl neofetch git lsof iftop \
  libsqlite3-dev libz-dev gcc g++ libreadline-dev \
  zlib1g-dev libssl-dev dos2unix cron dnsutils \
  tcpdump dsniff grepcidr

wget https://github.com/jgmdev/ddos-deflate/archive/master.zip -O ddos.zip
unzip ddos.zip
cd ddos-deflate-master
./install.sh
cd

# Install Ruby gem (colorized text)
gem install lolcat

# Enable and start logging service
systemctl enable rsyslog
systemctl start rsyslog

# Configure vnstat for network monitoring
if ! command -v vnstat &> /dev/null; then
    apt install -y vnstat
fi
INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
mkdir -p /var/lib/vnstat
chown vnstat:vnstat /var/lib/vnstat
if [ ! -f "/var/lib/vnstat/$INTERFACE" ]; then
    vnstat -u -i "$INTERFACE"
fi
systemctl daemon-reload
systemctl enable vnstat
systemctl restart vnstat

# Create secure PAM configuration
wget -q -O /etc/pam.d/common-password "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/password"
chmod +x /etc/pam.d/common-password

# reload iptables
cat > /etc/rc.local <<'EOF'
#!/bin/sh -e
netfilter-persistent reload
exit 0
EOF
chmod +x /etc/rc.local

cat > /etc/systemd/system/rc-local.service <<'EOF'
[Unit]
Description=/etc/rc.local compatibility
ConditionPathExists=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local start
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rc-local
systemctl start rc-local

# disable ipv6
grep -qxF 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
grep -qxF 'net.ipv6.conf.default.disable_ipv6 = 1' /etc/sysctl.conf || echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf

sysctl -p

# Remove old NGINX
apt purge -y nginx nginx-common nginx-core nginx-full
apt remove -y nginx nginx-common nginx-core nginx-full
apt autoremove -y

# Install Nginx
apt update -y && apt install -y nginx

# Remove default configs
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
rm -f /usr/share/nginx/html/index.html
rm -f /etc/nginx/conf.d/default.conf
rm -f /etc/nginx/conf.d/vps.conf

# Download custom configs
wget -q -O /etc/nginx/nginx.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/nginx.conf"
#mkdir -p /home/vps/public_html
#chown -R www-data:www-data /home/vps/public_html
#wget -q -O /etc/nginx/conf.d/vps.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/vps.conf"

# Add systemd override (fix for early startup)
mkdir -p /etc/systemd/system/nginx.service.d
printf "[Service]\nExecStartPost=/bin/sleep 0.1\n" > /etc/systemd/system/nginx.service.d/override.conf

# Restart Nginx
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

# Setup web root directory
wget -q -O /usr/share/nginx/html/index.html "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/index"

# install badvpn
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/install-udpgw.sh | bash

# BadVPN Control Menu
wget -O /usr/bin/m-badvpn "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/m-badvpn.sh"
chmod +x /usr/bin/m-badvpn

# setup sshd
cat > /etc/ssh/sshd_config <<EOF
# =========================================
# Minimal & Safe SSHD Configuration
# =========================================

# Ports
Port 22
Port 2222

# Authentication
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
PubkeyAuthentication yes

# Connection Settings
AllowTcpForwarding yes
PermitTTY yes
X11Forwarding no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:100

# Security & Performance
UsePAM yes
ChallengeResponseAuthentication no
UseDNS no
Compression delayed
GSSAPIAuthentication no

# Logging
SyslogFacility AUTH
LogLevel INFO
EOF

# Download banner
BANNER_URL="https://raw.githubusercontent.com/givps/AutoScriptXray/master/banner/banner.conf"
BANNER_FILE="/etc/issue.net"
wget -q -O "$BANNER_FILE" "$BANNER_URL"
if ! grep -q "^Banner $BANNER_FILE" /etc/ssh/sshd_config; then
    echo "Banner $BANNER_FILE" >> /etc/ssh/sshd_config
fi

systemctl restart sshd
systemctl enable sshd

# install dropbear
apt -y install dropbear

cat > /etc/default/dropbear <<EOF
# Dropbear configuration
NO_START=0
DROPBEAR_PORT=110
DROPBEAR_EXTRA_ARGS="-p 109"
EOF

echo "/bin/false" >> /etc/shells
echo "/usr/sbin/nologin" >> /etc/shells

systemctl daemon-reload
systemctl enable dropbear
systemctl start dropbear

dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key
systemctl restart dropbear

# ==============================================
# SSLH Multi-port Installer
# ==============================================
# Update system & install dependencies
apt update -y
apt install -y sslh wget build-essential libconfig-dev iproute2
# Buat systemd service type = simple/forking
cat > /etc/systemd/system/sslh.service <<'EOF'
[Unit]
Description=SSL/SSH/OpenVPN/XMPP/tinc port multiplexer
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p /run/sslh
ExecStartPre=/bin/chown root:root /run/sslh
ExecStart=/usr/sbin/sslh \
  --listen 0.0.0.0:443 \
  --listen 0.0.0.0:80 \
  --ssh 127.0.0.1:22 \
  --openvpn 127.0.0.1:1196 \
  --tls 127.0.0.1:4433 \
  --http 127.0.0.1:8080 \
  --on-timeout tls \
  --timeout 2 \
  --pidfile /run/sslh/sslh.pid \
  --foreground
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd dan start service
systemctl daemon-reload
systemctl enable sslh
systemctl start sslh

# install stunnel
apt install -y stunnel4

cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

# --- SSH over TLS ---
[ssh-tls]
accept = 222
connect = 127.0.0.1:22

# --- Dropbear over TLS ---
[dropbear-tls]
accept = 333
connect = 127.0.0.1:110

# --- WSS over TLS ---
[wss-tls]
accept = 444
connect = 127.0.0.1:1444

# --- TOR over TLS ---
[tor-tls]
accept = 777
connect = 127.0.0.1:9040

# --- OpenVPN over TLS ---
[openvpn-tls]
accept = 8443
connect = 127.0.0.1:1196
EOF

# make a certificate
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 3650 \
-subj "/C=ID/ST=Jakarta/L=Jakarta/O=givps/OU=IT/CN=localhost/emailAddress=admin@localhost"
cat key.pem cert.pem > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

cat > /etc/default/stunnel4 <<EOF
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
PPP_RESTART=0
EOF

systemctl daemon-reload
systemctl enable stunnel4
systemctl start stunnel4

# install tor
apt install -y tor

cat > /etc/tor/torrc <<'EOF'
Log notice file /var/log/tor/notices.log
SOCKSPort 127.0.0.1:9050
TransPort 127.0.0.1:9040
DNSPort 127.0.0.1:5353
AvoidDiskWrites 1
RunAsDaemon 1
ControlPort 9051
CookieAuthentication 1
EOF

# disable auto start after reboot
systemctl disable tor
systemctl stop tor
# enable auto start after reboot
#systemctl restart tor
#systemctl enable tor

#iptables -t nat -L TOR &>/dev/null || iptables -t nat -N TOR
#TOR_UID=$(id -u debian-tor 2>/dev/null || echo 0)
#iptables -t nat -C TOR -m owner --uid-owner $TOR_UID -j RETURN 2>/dev/null || \
#iptables -t nat -A TOR -m owner --uid-owner $TOR_UID -j RETURN
#iptables -t nat -C TOR -d 127.0.0.0/8 -j RETURN 2>/dev/null || \
#iptables -t nat -A TOR -d 127.0.0.0/8 -j RETURN
#iptables -t nat -C TOR -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
#iptables -t nat -A TOR -p udp --dport 53 -j REDIRECT --to-ports 5353
#iptables -t nat -C TOR -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || \
#iptables -t nat -A TOR -p tcp -j REDIRECT --to-ports 9040
#iptables -t nat -C OUTPUT -p tcp -j TOR 2>/dev/null || \
#iptables -t nat -I OUTPUT -p tcp -j TOR

# Simpan rules
#netfilter-persistent save
#netfilter-persistent reload

# install fail2ban
apt -y install fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 31536000
findtime = 600
maxretry = 3
banaction = iptables-multiport
backend = auto

[sshd]
enabled  = true
port     = 22,2222
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
findtime = 600
bantime  = 31536000
backend  = auto

[openvpn-tcp]
enabled  = true
port     = 1195
filter   = openvpn
logpath  = /var/log/openvpn/server-tcp.log
maxretry = 3
bantime  = 31536000

[openvpn-udp]
enabled  = true
port     = 51825
filter   = openvpn
logpath  = /var/log/openvpn/server-udp.log
maxretry = 3
bantime  = 31536000

[openvpn-ssl]
enabled  = true
port     = 443
filter   = openvpn
logpath  = /var/log/openvpn/server-ssl.log
maxretry = 3
bantime  = 31536000

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = iptables-allports[name=recidive, protocol=all]
bantime = 31536000
findtime = 600
maxretry = 3
EOF

systemctl daemon-reload
systemctl enable fail2ban
systemctl start fail2ban

# install blokir torrent
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/auto-torrent-blocker.sh | bash

# download script
cd /usr/bin
# menu
wget -O menu "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/menu.sh"
wget -O m-vmess "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-vmess.sh"
wget -O m-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-vless.sh"
wget -O running "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/running.sh"
wget -O clearcache "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/clearcache.sh"
wget -O m-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-ssws.sh"
wget -O m-trojan "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-trojan.sh"

# menu ssh ovpn
wget -O m-sshovpn "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-sshovpn.sh"
wget -O usernew "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/usernew.sh"
wget -O trial "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/trial.sh"
wget -O renew "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/renew.sh"
wget -O delete "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/delete.sh"
wget -O cek "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cek.sh"
wget -O member "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/member.sh"
wget -O autodelete "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/autodelete.sh"
wget -O autokill "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/autokill.sh"
wget -O ceklim "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/ceklim.sh"
wget -O autokick "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/autokick.sh"
wget -O sshws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/sshws.sh"
wget -O lock-unlock "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/lock-unlock.sh"

# menu system
wget -O m-system "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-system.sh"
wget -O m-domain "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-domain.sh"
wget -O crt "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/crt.sh"
wget -O auto-reboot "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/auto-reboot.sh"
wget -O restart "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/restart.sh"
wget -O bw "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/bw.sh"
wget -O m-tcp "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/tcp.sh"
wget -O xp "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/xp.sh"
wget -O sshws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/sshws.sh"
wget -O m-dns "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-dns.sh"
wget -O m-tor "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-tor.sh"

chmod +x menu
chmod +x m-vmess
chmod +x m-vless
chmod +x running
chmod +x clearcache
chmod +x m-ssws
chmod +x m-trojan

chmod +x m-sshovpn
chmod +x usernew
chmod +x trial
chmod +x renew
chmod +x delete
chmod +x cek
chmod +x member
chmod +x autodelete
chmod +x autokill
chmod +x ceklim
chmod +x autokick
chmod +x sshws
chmod +x lock-unlock

chmod +x m-system
chmod +x m-domain
chmod +x crt
chmod +x auto-reboot
chmod +x restart
chmod +x bw
chmod +x m-tcp
chmod +x xp
chmod +x sshws
chmod +x m-dns
chmod +x m-tor

# Install speedtest (using modern method)
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
apt-get install -y speedtest || true

cat > /etc/cron.d/re_otm <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 2 * * * root /sbin/reboot
EOF

cat > /etc/cron.d/xp_otm <<EOF
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
EOF

cat > /home/re_otm <<EOF
7
EOF

systemctl daemon-reload
systemctl enable cron
systemctl start cron

# remove unnecessary files
apt autoclean -y >/dev/null 2>&1

if dpkg -s unscd >/dev/null 2>&1; then
apt -y remove --purge unscd >/dev/null 2>&1
fi

apt-get -y --purge remove samba* >/dev/null 2>&1
apt-get -y --purge remove apache2* >/dev/null 2>&1
apt-get -y --purge remove bind9* >/dev/null 2>&1
apt-get -y remove sendmail* >/dev/null 2>&1
apt autoremove -y >/dev/null 2>&1

