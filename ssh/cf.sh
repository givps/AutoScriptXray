#!/bin/bash
# ==============================
# Auto update DNS Cloudflare (robust)
# ==============================
set -euo pipefail

# ==============================
# Colors
# ==============================
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

#delete old
rm -f /usr/local/etc/xray/domain /root/domain
mkdir -p /var/log
# ==============================
# Dependencies
# ==============================
for cmd in jq curl wget; do
    command -v $cmd >/dev/null 2>&1 || { apt update; apt install -y $cmd; }
done

# ==============================
# Config
# ==============================
DOMAIN="ipgivpn.my.id"
CF_ZONE_ID="bf7189e2d65747e6b9a0c85786652e8f"
CF_TOKEN="XCu7wHsxlkbcU3GSPOEvl1BopubJxA9kDcr-Tkt8"
IP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)

mkdir -p /etc/xray /var/lib/vps

log() { echo -e "[${yellow}$(date '+%H:%M:%S')${nc}] $*"; }

log "Public IP detected: ${green}$IP${nc}"

# ==============================
# Curl wrapper with retry
# ==============================
curl_retry() {
    local CMD=("$@")
    local MAX_RETRY=5 COUNT=0
    until [ $COUNT -ge $MAX_RETRY ]; do
        if RESPONSE=$( "${CMD[@]}" 2>/dev/null ); then
            echo "$RESPONSE"
            return 0
        fi
        COUNT=$((COUNT+1))
        log "${red}Network/API call failed. Retry $COUNT/$MAX_RETRY...${nc}"
        sleep 3
    done
    log "${red}Network/API failed after $MAX_RETRY retries. Exiting...${nc}"
    exit 1
}

# ==============================
# Check Cloudflare API token
# ==============================
check_token() {
    local RES
    RES=$(curl_retry curl -sLX GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json")
    if [[ $(echo "$RES" | jq -r '.success') != "true" ]]; then
        log "${red}Invalid API token. Check CF_TOKEN.${nc}"
        exit 1
    fi
    log "${green}API token valid.${nc}"
}

# ==============================
# Check zone exists
# ==============================
check_zone() {
    local RES
    RES=$(curl_retry curl -sLX GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_TOKEN" \
        -H "Content-Type: application/json")
    if [[ $(echo "$RES" | jq -r '.success') != "true" ]]; then
        log "${red}Zone ID not found or token lacks permission.${nc}"
        exit 1
    fi
    log "${green}Zone ID valid.${nc}"
}

# ==============================
# Generate random subdomain
# ==============================
generate_subdomain() {
    echo "asx$(tr -dc 0-9 </dev/urandom | head -c5).${DOMAIN}"
}

# ==============================
# Create or update DNS record
# ==============================
create_or_update() {
    local NAME=$1
    local TYPE=$2
    local CONTENT=$3
    local RECORD_ID
    RECORD_ID=$(curl_retry curl -sLX GET \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${NAME}" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

    local DATA="{\"type\":\"${TYPE}\",\"name\":\"${NAME}\",\"content\":\"${CONTENT}\",\"ttl\":120,\"proxied\":false}"

    if [[ -z "$RECORD_ID" ]]; then
        RESPONSE=$(curl_retry curl -sLX POST \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CF_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$DATA")
        log "Creating $TYPE record for $NAME..."
    else
        RESPONSE=$(curl_retry curl -sLX PUT \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
            -H "Authorization: Bearer ${CF_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$DATA")
        log "Updating $TYPE record for $NAME..."
    fi

    if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
        return 0
    else
        log "${red}Failed to create/update $TYPE record for $NAME.${nc}"
        echo "$RESPONSE" | jq -r '.errors'
        return 1
    fi
}

# ==============================
# Main flow
# ==============================
check_token
check_zone

log "Generating available subdomain..."
while true; do
    SUB_DOMAIN=$(generate_subdomain)
    EXISTS=$(curl_retry curl -sLX GET \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${SUB_DOMAIN}" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result | length')
    [[ "$EXISTS" -eq 0 ]] && break
done

WILDCARD_DOMAIN="*.${SUB_DOMAIN}"

log "Subdomain selected: ${green}$SUB_DOMAIN${nc}"
log "Wildcard domain: ${green}$WILDCARD_DOMAIN${nc}"

# Main A record
if create_or_update "$SUB_DOMAIN" "A" "$IP"; then
    log "${green}Main A record created successfully.${nc}"
else
    log "${yellow}Main A record failed. Will fallback to wildcard CNAME only.${nc}"
fi

# Wildcard record (A or CNAME)
if ! create_or_update "$WILDCARD_DOMAIN" "A" "$IP"; then
    log "${yellow}Wildcard A record failed — fallback to CNAME...${nc}"
    create_or_update "$WILDCARD_DOMAIN" "CNAME" "$SUB_DOMAIN"
fi

# Save info
echo "$SUB_DOMAIN" | tee /usr/local/etc/xray/domain /root/domain >/dev/null

# Log
{
    echo "============================="
    echo " Domain Info"
    echo "============================="
    echo "Main Domain : $SUB_DOMAIN"
    echo "Wildcard    : $WILDCARD_DOMAIN"
    echo "Public IP   : $IP"
    echo "Created at  : $(date)"
    echo
} >> /var/log/domain.txt

log "${green}Done! Domain $SUB_DOMAIN and wildcard $WILDCARD_DOMAIN created.${nc}"

