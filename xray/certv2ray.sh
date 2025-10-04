#!/bin/bash
# =========================================
# Quick Setup | Script Setup Manager
# Edition : Stable Edition 1.2 (Wildcard API)
# Author  : givps
# License : MIT
# =========================================

# Pewarna
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'

# ==========================================
clear
MYIP=$(wget -qO- ipv4.icanhazip.com)
echo -e "[ ${GREEN}INFO${NC} ] Detected VPS IP: $MYIP"
sleep 1

if grep -qw "XRAY" /root/log-install.txt; then
    domainlama=$(cat /etc/xray/domain 2>/dev/null)
else
    domainlama=$(cat /etc/v2ray/domain 2>/dev/null)
fi

# ===== DOMAIN CONFIG =====
DEFAULT_DOMAIN="givps.com"

# Minta input manual jika mau ganti, default givps.com
read -rp "Masukkan domain utama (tanpa www) [default: $DEFAULT_DOMAIN]: " input_domain
domain="${input_domain:-$DEFAULT_DOMAIN}"

clear
echo -e "[ ${GREEN}INFO${NC} ] Menggunakan domain: $domain"
sleep 1

# ===== Pastikan Cloudflare API token tersedia =====
if [[ -z "$CF_Token" ]]; then
    echo ""
    echo -e "[ ${ORANGE}WARNING${NC} ] Cloudflare API Token belum ditemukan."
    echo "Masukkan Cloudflare API Token kamu:"
    read -rp "CF_Token : " CF_Token
    echo ""
fi
export CF_Token="$CF_Token"

# ===== Stop service yang pakai port 80 (kalau ada) =====
Cek=$(lsof -i:80 | awk 'NR==2 {print $1}')
if [[ ! -z "$Cek" ]]; then
    echo -e "[ ${ORANGE}WARNING${NC} ] Port 80 digunakan oleh: $Cek"
    systemctl stop $Cek
    sleep 1
fi

systemctl stop nginx >/dev/null 2>&1

# ===== Mulai proses wildcard SSL =====
echo -e "[ ${GREEN}INFO${NC} ] Mengeluarkan wildcard SSL untuk *.$domain ..."
sleep 1

/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

/root/.acme.sh/acme.sh --issue \
  --dns dns_cf \
  -d "$domain" \
  -d "*.$domain" \
  --keylength ec-256

# ===== Pasang sertifikat ke direktori Xray =====
/root/.acme.sh/acme.sh --install-cert -d "$domain" \
  --fullchainpath /etc/xray/xray.crt \
  --keypath /etc/xray/xray.key \
  --ecc

# ===== Simpan domain =====
mkdir -p /etc/xray /etc/v2ray
echo "$domain" > /etc/xray/domain
echo "$domain" > /etc/v2ray/domain

# ===== Restart service =====
systemctl restart nginx >/dev/null 2>&1
systemctl restart xray >/dev/null 2>&1

echo ""
echo -e "[ ${GREEN}SUCCESS${NC} ] Wildcard SSL berhasil dibuat!"
echo -e "Domain   : *.$domain"
echo -e "Cert     : /etc/xray/xray.crt"
echo -e "Key      : /etc/xray/xray.key"
echo ""
read -n 1 -s -r -p "Tekan sembarang tombol untuk kembali ke menu..."
m-domain
