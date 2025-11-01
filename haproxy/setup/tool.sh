#!/bin/bash
# =========================================
# install ssh tool
# =========================================

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
  zlib1g-dev libssl-dev dos2unix

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

# /etc/rc.local
cat > /etc/rc.local <<'EOF'
#!/bin/sh -e
# rc.local file created by setup script

# Reload netfilter rules
netfilter-persistent reload

# Disable IPv6
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6

exit 0
EOF

chmod +x /etc/rc.local

cat > /etc/systemd/system/rc-local.service <<'EOF'
[Unit]
Description=/etc/rc.local Compatibility
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

systemctl daemon-reload
systemctl enable rc-local
systemctl start rc-local

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
mkdir -p /home/vps/public_html
chown -R www-data:www-data /home/vps/public_html
#wget -q -O /etc/nginx/conf.d/vps.conf "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/vps.conf"

# Add systemd override (fix for early startup)
mkdir -p /etc/systemd/system/nginx.service.d
printf "[Service]\nExecStartPost=/bin/sleep 0.1\n" > /etc/systemd/system/nginx.service.d/override.conf

# Restart Nginx
systemctl daemon-reload
systemctl start nginx
systemctl enable nginx

# Setup web root directory
wget -q -O /usr/share/nginx/html/index.html "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/index"

# install badvpn
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/install-udpgw.sh | bash

# BadVPN Control Menu
wget -O /usr/bin/m-badvpn "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/m-badvpn.sh"
chmod +x /usr/bin/m-badvpn

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
port = 22,2222
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = 22,2222
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

# Download banner
BANNER_URL="https://raw.githubusercontent.com/givps/AutoScriptXray/master/banner/banner.conf"
BANNER_FILE="/etc/issue.net"
wget -q -O "$BANNER_FILE" "$BANNER_URL"
if ! grep -q "^Banner $BANNER_FILE" /etc/ssh/sshd_config; then
    echo "Banner $BANNER_FILE" >> /etc/ssh/sshd_config
fi

systemctl restart sshd

# install blokir torrent
wget -qO- https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/auto-torrent-blocker.sh | bash

# download script
cd /usr/bin
# menu
wget -O menu "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/menu/menu.sh"
wget -O m-vmess "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-vmess.sh"
wget -O m-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-vless.sh"
wget -O running "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/menu/running.sh"
wget -O clearcache "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/clearcache.sh"
wget -O m-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-ssws.sh"
wget -O m-trojan "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-trojan.sh"

# menu ssh ovpn
wget -O m-sshovpn "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/menu/m-sshovpn.sh"
wget -O usernew "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/usernew.sh"
wget -O trial "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/trial.sh"
wget -O renew "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/renew.sh"
wget -O delete "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/delete.sh"
wget -O cek "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cek.sh"
wget -O member "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/member.sh"
wget -O autodelete "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/autodelete.sh"
wget -O autokill "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/autokill.sh"
wget -O ceklim "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/ceklim.sh"
wget -O autokick "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/autokick.sh"
wget -O sshws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/sshws.sh"
wget -O lock-unlock "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/lock-unlock.sh"

# menu system
wget -O m-system "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/menu/m-system.sh"
wget -O m-domain "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/m-domain.sh"
wget -O certv2ray "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/certv2ray.sh"
wget -O auto-reboot "https://raw.githubusercontent.com/givps/AutoScriptXray/master/menu/auto-reboot.sh"
wget -O restart "https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/menu/restart.sh"
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

