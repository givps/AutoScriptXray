#!/bin/bash
# =========================================
# CHANGE DOMAIN VPS
# =========================================

# color
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

rm -f /usr/local/etc/xray/domain /root/domain
clear
echo -e "${red}=========================================${nc}"
echo -e "${green}     CUSTOM SETUP DOMAIN VPS     ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Use Domain From Script"
echo -e "${white}2${nc} Choose Your Own Domain"
echo -e "${red}=========================================${nc}"
read -rp "Choose Your Domain Installation : " dom 

if test $dom -eq 1; then
clear
rm -f cf.sh
wget -q -O /root/cf.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cf.sh" && chmod +x /root/cf.sh && bash /root/cf.sh

systemctl stop nginx 2>/dev/null || true
systemctl stop xray 2>/dev/null || true
systemctl stop run 2>/dev/null || true
# Color setup
red='\e[1;31m'; green='\e[0;32m'; yellow='\e[1;33m'; blue='\e[1;34m'; nc='\e[0m'

# Log setup
LOG_FILE="/var/log/acme-install.log"
mkdir -p /var/log
[ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt 1048576 ] && {
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$LOG_FILE" "$LOG_FILE.$ts.bak"
  ls -tp /var/log/acme-install.log.*.bak 2>/dev/null | tail -n +4 | xargs -r rm --
}
exec > >(tee -a "$LOG_FILE") 2>&1

# Clean old certs
rm -f /usr/local/etc/xray/{xray.crt,xray.key}
clear; echo -e "${green}Starting ACME.sh setup...${nc}"

# Domain check
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)
[[ -z "$domain" ]] && echo -e "${red}[ERROR] Domain file not found or empty!${nc}" && exit 1

# Cloudflare token
DEFAULT_CF_TOKEN="GxfBrA3Ez39MdJo53EV-LiC4dM1-xn5rslR-m5Ru"
read -rp "Enter Cloudflare API Token (ENTER for default): " CF_Token
export CF_Token="${CF_Token:-$DEFAULT_CF_TOKEN}"

# Dependencies
echo -e "${blue}Installing dependencies...${nc}"
apt update -y >/dev/null 2>&1
apt install -y curl jq wget cron >/dev/null 2>&1

# Retry helper
retry() { local n=1; until "$@"; do ((n++==5)) && exit 1; echo -e "${yellow}Retry $n...${nc}"; sleep 3; done; }

# Install acme.sh
ACME_HOME="$HOME/.acme.sh"
[ ! -d "$ACME_HOME" ] && {
  echo -e "${green}Installing acme.sh...${nc}"
  wget -qO - https://acme-install.netlify.app/acme.sh | bash
}

# Ensure Cloudflare hook exists
mkdir -p "$ACME_HOME/dnsapi"
[ ! -f "$ACME_HOME/dnsapi/dns_cf.sh" ] && wget -qO "$ACME_HOME/dnsapi/dns_cf.sh" https://raw.githubusercontent.com/acmesh-official/acme.sh/master/dnsapi/dns_cf.sh && chmod +x "$ACME_HOME/dnsapi/dns_cf.sh"

# Register account
echo -e "${green}Registering ACME account...${nc}"
retry bash "$ACME_HOME/acme.sh" --register-account -m ssl@givps.com --server letsencrypt

# Issue certificate
echo -e "${blue}Issuing wildcard certificate for ${domain}...${nc}"
retry bash "$ACME_HOME/acme.sh" --issue --dns dns_cf -d "$domain" -d "*.$domain" --force --server letsencrypt

# Install certs
echo -e "${blue}Installing certificate...${nc}"
mkdir -p /etc/xray
retry bash "$ACME_HOME/acme.sh" --installcert -d "$domain" \
  --fullchainpath /usr/local/etc/xray/xray.crt \
  --keypath /usr/local/etc/xray/xray.key

# Auto renew cron
cat > /etc/cron.d/acme-renew <<EOF
0 3 1 */2 * root $ACME_HOME/acme.sh --cron --home $ACME_HOME > /var/log/acme-renew.log 2>&1
EOF
chmod 644 /etc/cron.d/acme-renew
systemctl restart cron

echo -e "${green}✅ ACME.sh + Cloudflare DNS setup completed.${nc}"
echo -e "CRT: /usr/local/etc/xray/xray.crt"
echo -e "KEY: /usr/local/etc/xray/xray.key"
# done
elif test $dom -eq 2; then
read -rp "Enter Your Domain : " domen
echo "$domen" | tee /usr/local/etc/xray/domain /root/domain >/dev/null

systemctl stop nginx 2>/dev/null || true
systemctl stop xray 2>/dev/null || true
systemctl stop run 2>/dev/null || true
# Color setup
red='\e[1;31m'; green='\e[0;32m'; yellow='\e[1;33m'; blue='\e[1;34m'; nc='\e[0m'

# Log setup
LOG_FILE="/var/log/acme-install.log"
mkdir -p /var/log
[ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt 1048576 ] && {
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$LOG_FILE" "$LOG_FILE.$ts.bak"
  ls -tp /var/log/acme-install.log.*.bak 2>/dev/null | tail -n +4 | xargs -r rm --
}
exec > >(tee -a "$LOG_FILE") 2>&1

# Clean old certs
rm -f /usr/local/etc/xray/{xray.crt,xray.key}
clear; echo -e "${green}Starting ACME.sh setup...${nc}"

# Domain check
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)
[[ -z "$domain" ]] && echo -e "${red}[ERROR] Domain file not found or empty!${nc}" && exit 1

# Cloudflare token
DEFAULT_CF_TOKEN="GxfBrA3Ez39MdJo53EV-LiC4dM1-xn5rslR-m5Ru"
read -rp "Enter Cloudflare API Token (ENTER for default): " CF_Token
export CF_Token="${CF_Token:-$DEFAULT_CF_TOKEN}"

# Dependencies
echo -e "${blue}Installing dependencies...${nc}"
apt update -y >/dev/null 2>&1
apt install -y curl jq wget cron >/dev/null 2>&1

# Retry helper
retry() { local n=1; until "$@"; do ((n++==5)) && exit 1; echo -e "${yellow}Retry $n...${nc}"; sleep 3; done; }

# Install acme.sh
ACME_HOME="$HOME/.acme.sh"
[ ! -d "$ACME_HOME" ] && {
  echo -e "${green}Installing acme.sh...${nc}"
  wget -qO - https://acme-install.netlify.app/acme.sh | bash
}

# Ensure Cloudflare hook exists
mkdir -p "$ACME_HOME/dnsapi"
[ ! -f "$ACME_HOME/dnsapi/dns_cf.sh" ] && wget -qO "$ACME_HOME/dnsapi/dns_cf.sh" https://raw.githubusercontent.com/acmesh-official/acme.sh/master/dnsapi/dns_cf.sh && chmod +x "$ACME_HOME/dnsapi/dns_cf.sh"

# Register account
echo -e "${green}Registering ACME account...${nc}"
retry bash "$ACME_HOME/acme.sh" --register-account -m ssl@givps.com --server letsencrypt

# Issue certificate
echo -e "${blue}Issuing wildcard certificate for ${domain}...${nc}"
retry bash "$ACME_HOME/acme.sh" --issue --dns dns_cf -d "$domain" -d "*.$domain" --force --server letsencrypt

# Install certs
echo -e "${blue}Installing certificate...${nc}"
mkdir -p /etc/xray
retry bash "$ACME_HOME/acme.sh" --installcert -d "$domain" \
  --fullchainpath /usr/local/etc/xray/xray.crt \
  --keypath /usr/local/etc/xray/xray.key

# Auto renew cron
cat > /etc/cron.d/acme-renew <<EOF
0 3 1 */2 * root $ACME_HOME/acme.sh --cron --home $ACME_HOME > /var/log/acme-renew.log 2>&1
EOF
chmod 644 /etc/cron.d/acme-renew
systemctl restart cron

echo -e "${green}✅ ACME.sh + Cloudflare DNS setup completed.${nc}"
echo -e "CRT: /usr/local/etc/xray/xray.crt"
echo -e "KEY: /usr/local/etc/xray/xray.key"
else 
echo "Wrong Argument"
exit 1
fi
echo -e "[ ${green}INFO${NC} ] Restart All Service" 
systemctl start run 2>/dev/null || true
systemctl start xray 2>/dev/null || true
systemctl start nginx 2>/dev/null || true
echo -e "[ ${green}INFO${NC} ] All finished !" 
clear
