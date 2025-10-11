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

# Configure vnstat for network monitoring
systemctl enable vnstat

# Create secure PAM configuration
cat > /etc/pam.d/common-password << 'EOF'
#
# /etc/pam.d/common-password - password-related modules common to all services
#
# This file is included from other service-specific PAM config files,
# and should contain a list of modules that define the services to be
# used to change user passwords.  The default is pam_unix.

# Explanation of pam_unix options:
#
# The "sha512" option enables salted SHA512 passwords.  Without this option,
# the default is Unix crypt.  Prior releases used the option "md5".
#
# The "obscure" option replaces the old `OBSCURE_CHECKS_ENAB' option in
# login.defs.
#
# See the pam_unix manpage for other options.

# As of pam 1.0.1-6, this file is managed by pam-auth-update by default.
# To take advantage of this, it is recommended that you configure any
# local modules either before or after the default block, and use
# pam-auth-update to manage selection of other modules.  See
# pam-auth-update(8) for details.

# here are the per-package modules (the "Primary" block)
password	[success=1 default=ignore]	pam_unix.so obscure sha512
# here's the fallback if no module succeeds
password	requisite			pam_deny.so
# prime the stack with a positive return value if there isn't one already;
# this avoids us returning an error just because nothing sets a success code
# since the modules above will each just jump around
password	required			pam_permit.so
# and here are more per-package modules (the "Additional" block)
# end of pam-auth-update config
EOF

# Set correct permissions
chmod 644 /etc/pam.d/common-password

# Edit file /etc/systemd/system/rc-local.service
cat > /etc/systemd/system/rc-local.service <<-END
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
END

# nano /etc/rc.local
cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
# By default this script does nothing.
exit 0
END

# Ubah izin akses
chmod +x /etc/rc.local

# enable rc local
systemctl enable rc-local

# disable ipv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

# set time GMT +7
ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
apt install -y ntp
systemctl enable ntp

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

echo "=== install dropbear ==="
# install dropbear
apt -y install dropbear
cat > /etc/default/dropbear << EOF
# Dropbear configuration
NO_START=0
DROPBEAR_PORT=110
EOF

echo "/bin/false" >> /etc/shells
echo "/usr/sbin/nologin" >> /etc/shells

systemctl enable dropbear

# install stunnel
apt install stunnel4 -y
cat > /etc/stunnel/stunnel.conf <<-END
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
foreground = no
compression = zlib
sslVersion = TLSv1.2
options = NO_SSLv2
options = NO_SSLv3
options = NO_TLSv1
options = NO_TLSv1.1
renegotiation = no
sessionCacheSize = 1000
sessionTimeout = 300

# =====================================
# SSH Services
# =====================================
[openssh]
accept = 222
connect = 127.0.0.1:22

[dropbear]
accept = 777
connect = 127.0.0.1:110

# =====================================
# WebSocket SSL (WSS)
# =====================================
[ws-dropbear-ssl]
accept = 444
connect = 127.0.0.1:143

[ws-stunnel-ssl]
accept = 447
connect = 127.0.0.1:144

# =====================================
# WebSocket Non-SSL (WS)
# =====================================
[ws-dropbear]
accept = 333
connect = 127.0.0.1:143
protocol = none

[ws-stunnel]
accept = 337
connect = 127.0.0.1:144
protocol = none

END

# =========================================
# Basic Firewall Setup (iptables)
# =========================================

# Allow loopback (localhost)
iptables -A INPUT -i lo -j ACCEPT

# Allow established / related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow all used SSH ports
iptables -A INPUT -p tcp -m multiport --dports 22,222 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 110,777 -j ACCEPT

# HTTP/HTTPS
iptables -A INPUT -p tcp -m multiport --dports 80,81,443 -j ACCEPT

# Websocket
iptables -A INPUT -p tcp -m multiport --dports 143,333,444 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 144,337,447 -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Drop all other connections that do not match the above rules
iptables -A INPUT -j DROP

# Save rules to rules.v4 file
iptables-save > /etc/iptables/rules.v4

# Save to persistent iptables configuration (auto restore on reboot)
netfilter-persistent save

# Reload to ensure active
netfilter-persistent reload

# make a certificate
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 3650 \
-subj "/C=ID/ST=Jakarta/L=Jakarta/O=givps/OU=IT/CN=localhost/emailAddress=admin@localhost"
cat key.pem cert.pem > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

cat > /etc/default/stunnel4 << EOF
ENABLED=1
FILES="/etc/stunnel/*.conf"
OPTIONS=""
PPP_RESTART=0
EOF

systemctl enable stunnel4

# install fail2ban
apt -y install fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
banaction = iptables-multiport

[sshd]
enabled = true
port = 22,110
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = 22,110
logpath = /var/log/auth.log
maxretry = 5
bantime = 86400
EOF

systemctl enable fail2ban

# Instal DDOS Deflate
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/auto-install-ddos.sh | bash

# // banner /etc/issue.net
wget -O /etc/issue.net "https://raw.githubusercontent.com/givps/AutoScriptXray/master/banner/banner.conf"
echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
sed -i 's@DROPBEAR_BANNER=""@DROPBEAR_BANNER="/etc/issue.net"@g' /etc/default/dropbear

systemctl enable sshd

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
wget -O speedtest "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/speedtest_cli.py"
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
chmod +x speedtest
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

cat > /etc/cron.d/re_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 2 * * * root /sbin/reboot
END

cat > /etc/cron.d/xp_otm <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
END

cat > /home/re_otm <<-END
7
END

systemctl enable cron

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

