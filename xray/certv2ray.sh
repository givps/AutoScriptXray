#!/bin/bash
# =========================================
# renew ssl
# =========================================
clear
red='\e[1;31m'
green='\e[0;32m'
purple='\e[0;35m'
orange='\e[0;33m'
nc='\e[0m'

echo -e "[ ${green}INFO${nc} ] Renew Certificate In Progress ~" 

systemctl stop nginx
systemctl stop xray
systemctl stop run
echo -e "[ ${green}INFO${nc} ] Starting Renew Certificate . . . " 

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
  wget -qO - https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/acme.sh | bash
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

echo -e "[ ${green}INFO${nc} ] Restart All Service" 

echo "$domain" > /usr/local/etc/xray/domain
echo "$domain" > /root/domain
systemctl start run
systemctl start xray
systemctl start nginx
echo -e "[ ${green}INFO${nc} ] All finished !" 

