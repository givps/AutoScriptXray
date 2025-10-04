#!/bin/bash
# =========================================
# Quick Setup | Cloudflare Wildcard SSL + A Record
# Edition : Stable 1.3
# Author  : givps
# License : MIT
# =========================================

# API Token = BnzEPlSNz6HugXhHTH_nwgN4tHzi_ItVU_jxMI5k

set -euo pipefail

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

# ===== DOMAIN CONFIG =====
DEFAULT_DOMAIN="givps.com"
read -rp "Masukkan domain utama (tanpa www) [default: $DEFAULT_DOMAIN]: " input_domain
DOMAIN="${input_domain:-$DEFAULT_DOMAIN}"

clear
echo -e "[ ${GREEN}INFO${NC} ] Menggunakan domain: $DOMAIN"
sleep 1

# ===== Cloudflare API Token =====
read -rp "Masukkan Cloudflare API Token (scoped DNS Edit) : " CF_Token
export CF_Token="$CF_Token"

# ===== Buat/Update A Record otomatis =====
SUB_DOMAIN="t1.$DOMAIN"   # Bisa diganti sesuai kebutuhan
echo -e "[ ${GREEN}INFO${NC} ] Membuat/Update A record: $SUB_DOMAIN → $MYIP"

# ===== GET ZONE ID =====
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN&status=active" \
  -H "Authorization: Bearer $CF_Token" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
    echo -e "[${RED}ERROR${NC}] Gagal mengambil Zone ID $DOMAIN"
    exit 1
fi

# ===== Cek Record =====
RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$SUB_DOMAIN" \
  -H "Authorization: Bearer $CF_Token" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [[ -z "$RECORD_ID" || "$RECORD_ID" == "null" ]]; then
    echo -e "[ ${GREEN}INFO${NC} ] Membuat A record baru..."
    RECORD_ID=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_Token" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"'"$SUB_DOMAIN"'","content":"'"$MYIP"'","ttl":120,"proxied":false}' | jq -r '.result.id')
else
    echo -e "[ ${GREEN}INFO${NC} ] Update A record..."
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
      -H "Authorization: Bearer $CF_Token" \
      -H "Content-Type: application/json" \
      --data '{"type":"A","name":"'"$SUB_DOMAIN"'","content":"'"$MYIP"'","ttl":120,"proxied":false}' >/dev/null
fi

# ===== Cek hasil =====
if [[ -z "$RECORD_ID" || "$RECORD_ID" == "null" ]]; then
    echo -e "[${RED}ERROR${NC}] Gagal membuat/update A record!"
    exit 1
fi

echo -e "[ ${GREEN}SUCCESS${NC} ] A record siap: $SUB_DOMAIN → $MYIP"

# ===== Mulai proses wildcard SSL =====
echo -e "[ ${GREEN}INFO${NC} ] Mengeluarkan wildcard SSL untuk *.$DOMAIN ..."
sleep 1

/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
/root/.acme.sh/acme.sh --issue \
  --dns dns_cf \
  -d "$DOMAIN" \
  -d "*.$DOMAIN" \
  --keylength ec-256

# ===== Pasang sertifikat ke direktori Xray/V2Ray =====
mkdir -p /etc/xray /etc/v2ray /etc/utama
/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --fullchainpath /etc/xray/xray.crt \
  --keypath /etc/xray/xray.key \
  --ecc

# ===== Simpan domain =====
echo "$DOMAIN" > /etc/xray/domain
echo "$DOMAIN" > /etc/v2ray/domain
echo "$DOMAIN" > /etc/utama/domain

# ===== Restart service =====
systemctl restart nginx >/dev/null 2>&1 || true
systemctl restart xray >/dev/null 2>&1 || true

echo ""
echo -e "[ ${GREEN}SUCCESS${NC} ] Wildcard SSL berhasil dibuat!"
echo -e "Domain       : *.$DOMAIN"
echo -e "A Record     : $SUB_DOMAIN → $MYIP"
echo -e "Cert         : /etc/xray/xray.crt"
echo -e "Key          : /etc/xray/xray.key"
echo ""
read -n 1 -s -r -p "Tekan sembarang tombol untuk kembali ke menu..."
m-domain
