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
apt upgrade -y

# Install iptables directly
apt install iptables iptables-persistent netfilter-persistent -y
apt-get remove --purge ufw firewalld -y
apt-get remove --purge exim4 -y

# Install all packages in single command (faster and more efficient)
apt install -y \
  shc wget curl figlet ruby python3 make cmake \
  iptables iptables-persistent netfilter-persistent \
  coreutils rsyslog net-tools htop screen \
  zip unzip nano sed gnupg bc jq bzip2 gzip \
  apt-transport-https build-essential dirmngr \
  libxml-parser-perl neofetch git lsof vnstat iftop \
  libsqlite3-dev libz-dev gcc g++ libreadline-dev \
  zlib1g-dev libssl-dev dos2unix

# Install Ruby gem
gem install lolcat

# Configure essential services
systemctl enable rsyslog
systemctl start rsyslog

# Configure vnstat for network monitoring
systemctl enable vnstat
systemctl start vnstat

# Create secure PAM configuration
wget -q -O /etc/pam.d/common-password "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/password"
chmod +x /etc/pam.d/common-password

# Edit file /etc/systemd/system/rc-local.service
cat > /etc/systemd/system/rc-local.service <<EOF
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
[Install]
WantedBy=multi-user.target
EOF

# nano /etc/rc.local
cat > /etc/rc.local <<EOF
#!/bin/sh -e
# rc.local
# By default this script does nothing.
exit 0
EOF

# Ubah izin akses
chmod +x /etc/rc.local

# enable rc local
systemctl enable rc-local
systemctl start rc-local

# disable ipv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

# Remove old NGINX
apt remove -y nginx nginx-common
apt purge -y nginx nginx-common
apt autoremove -y
apt update -y

# Install Nginx
apt update -y && apt install -y nginx

# Remove default configs
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
rm -f /etc/nginx/conf.d/default.conf
rm -f /etc/nginx/conf.d/vps.conf

# Download custom configs
wget -q -O /etc/nginx/nginx.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/nginx.conf"
wget -q -O /etc/nginx/conf.d/vps.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/vps.conf"

# Add systemd override (fix for early startup)
mkdir -p /etc/systemd/system/nginx.service.d
printf "[Service]\nExecStartPost=/bin/sleep 0.1\n" > /etc/systemd/system/nginx.service.d/override.conf

# Restart Nginx
systemctl enable nginx
systemctl start nginx

# Setup web root directory
mkdir -p /home/vps/public_html

# Download web files
wget -q -O /home/vps/public_html/index.html "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/index"

# Set ownership
chown -R www-data:www-data /home/vps/public_html

# install badvpn
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/install-udpgw.sh | bash

# BadVPN Control Menu
wget -O /usr/bin/m-badvpn "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/m-badvpn.sh"
chmod +x /usr/bin/m-badvpn

# Enable password auth for initial setup, but consider disabling later
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config

# Additional security settings
sed -i 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/#ClientAliveInterval 0/ClientAliveInterval 600/g' /etc/ssh/sshd_config
sed -i 's/#ClientAliveCountMax 3/ClientAliveCountMax 2/g' /etc/ssh/sshd_config
systemctl enable ssh
systemctl restart ssh

echo "=== install dropbear ==="
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

systemctl enable dropbear
systemctl start dropbear


# install stunnel
apt install stunnel4 -y
cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

# =====================================
# SSH
# =====================================
[ssh-ssl]
accept = 222
connect = 127.0.0.1:22

# =====================================
# Dropbear
# =====================================
[dropbear-ssl]
accept = 444
connect = 127.0.0.1:110
EOF

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH & Dropbear
iptables -A INPUT -p tcp -m multiport --dports 22,109,110,222,444 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp -m multiport --dports 80,81,443 -j ACCEPT

# Allow WebSocket ports
iptables -A INPUT -p tcp -m multiport --dports 1444,1445 -j ACCEPT

# Allow ping
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Masquerade outbound traffic
iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE

# Allow forwarding
iptables -P FORWARD ACCEPT

# Drop other inputs
iptables -A INPUT -j DROP

# Save
iptables-save > /etc/iptables/rules.v4
netfilter-persistent save
netfilter-persistent reload

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

systemctl enable stunnel4
systemctl start stunnel4

# install fail2ban
apt -y install fail2ban
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
banaction = iptables-multiport

[sshd]
enabled = true
port = 22,109,110
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = 22,109,110
logpath = /var/log/auth.log
maxretry = 5
bantime = 86400
EOF

systemctl enable fail2ban
systemctl start fail2ban

# Instal DDOS Deflate
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/auto-install-ddos.sh | bash

# // banner /etc/issue.net
wget -O /etc/issue.net "https://raw.githubusercontent.com/givps/AutoScriptXray/master/banner/banner.conf"
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
sed -i 's@DROPBEAR_BANNER=""@DROPBEAR_BANNER="/etc/issue.net"@g' /etc/default/dropbear

systemctl restart sshd

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
wget -O certv2ray "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/certv2ray.sh"
wget -O auto-reboot "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/auto-reboot.sh"
wget -O restart "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/restart.sh"
wget -O bw "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/bw.sh"
wget -O m-tcp "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/tcp.sh"
wget -O xp "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/xp.sh"
wget -O sshws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/sshws.sh"
wget -O m-dns "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-dns.sh"

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
chmod +x certv2ray
chmod +x auto-reboot
chmod +x restart
chmod +x bw
chmod +x m-tcp
chmod +x xp
chmod +x sshws
chmod +x m-dns

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

systemctl daemon-reload
systemctl restart rsyslog
systemctl restart vnstat
systemctl restart rc-local
systemctl restart nginx
systemctl restart dropbear
systemctl restart stunnel4
systemctl restart fail2ban
systemctl restart cron
