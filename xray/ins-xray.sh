#!/bin/bash
# ==========================================
# install xray & ssl
# ==========================================
# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

# Get domain
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)
mkdir -p /myinfo
country=$(curl -s https://api.country.is 2>/dev/null | jq -r '.country' 2>/dev/null)
if [[ -z "$country" || "$country" == "null" ]]; then
    country=$(curl -s https://ipinfo.io/json 2>/dev/null | jq -r '.country' 2>/dev/null)
fi
if [[ -z "$country" || "$country" == "null" ]]; then
    country="API limit..."
fi
sudo mkdir -p /myinfo
echo "$country" | tee /myinfo/country > /dev/null
# Install all packages in one command (more efficient)
echo -e "[ ${green}INFO${nc} ] Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y \
    iptables iptables-persistent \
    curl python3 socat xz-utils wget apt-transport-https \
    gnupg gnupg2 gnupg1 dnsutils lsb-release \
    cron bash-completion \
    zip pwgen openssl #netcat

# Clean up packages
echo -e "[ ${green}INFO${nc} ] Cleaning up..."
apt clean all && apt autoremove -y

# install xray
echo -e "[ ${green}INFO${nc} ] Downloading & Installing xray core"
# Create directory if doesn't exist and set permissions
echo -e "[ INFO ] Creating directories and setting permissions..."
# Craete folder
rm -f /usr/local/bin/xray
mkdir -p /usr/local/bin /usr/local/etc/xray /var/log/xray
touch /var/log/xray/{access,error}.log
id xray &>/dev/null || useradd -r -s /usr/sbin/nologin xray
###########################################################
# Xray official manual install v1.8.24 (auto-arch)
#VER=v1.8.24
#ARCH=$(uname -m)
#case $ARCH in
#  x86_64) F=Xray-linux-64.zip ;;
#  i*86) F=Xray-linux-32.zip ;;
#  aarch64) F=Xray-linux-arm64-v8a.zip ;;
#  armv7l) F=Xray-linux-arm32-v7a.zip ;;
#  *) echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
#esac

#curl -L -o x.zip https://github.com/XTLS/Xray-core/releases/download/$VER/$F
#unzip -qo x.zip xray && install -m 755 xray /usr/local/bin/xray
#chown -R root:root /usr/local/bin/xray
#chown -R xray:xray /usr/local/etc/xray /var/log/xray
#rm -rf x.zip xray && xray version
###########################################################
# xray official
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u xray
xray version
# Set ownership
chmod +x /usr/local/bin/xray
chown -R root:root /usr/local/bin/xray
chown -R xray:xray /usr/local/etc/xray
chown -R xray:xray /var/log/xray

# nginx stop
systemctl stop nginx

LOG_FILE="/var/log/acme-setup.log"
mkdir -p /var/log
rm -rf /root/.acme.sh
rm -f /usr/local/etc/xray/xray.crt
rm -f /usr/local/etc/xray/xray.key
# Rotate log if >1MB
[ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt 1048576 ] && {
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$LOG_FILE" "$LOG_FILE.$ts.bak"
  ls -tp /var/log/acme-setup.log.*.bak 2>/dev/null | tail -n +4 | xargs -r rm --
}

exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- Dependencies ----------
echo -e "[${blue}INFO${nc}] Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y curl wget socat cron openssl bash >/dev/null 2>&1

# ---------- Domain ----------
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)
[[ -z "$domain" ]] && echo -e "${red}[ERROR] Domain file not found!${nc}" && exit 1

# ---------- Cloudflare Token ----------
DEFAULT_CF_TOKEN="XCu7wHsxlkbcU3GSPOEvl1BopubJxA9kDcr-Tkt8"
read -rp "Enter Cloudflare API Token (ENTER for default): " CF_Token
export CF_Token="${CF_Token:-$DEFAULT_CF_TOKEN}"

# ---------- Retry helper ----------
retry() { local n=1; until "$@"; do ((n++==5)) && exit 1; echo -e "${yellow}Retry $n...${nc}"; sleep 3; done; }

# ---------- Install acme.sh ----------
ACME_HOME="/root/.acme.sh"
if [ ! -f "$ACME_HOME/acme.sh" ]; then
  echo -e "[${green}INFO${nc}] Installing acme.sh official..."
  curl https://get.acme.sh | sh
fi

# Reload ACME_HOME
export ACME_HOME="/root/.acme.sh"

# ---------- Ensure Cloudflare DNS hook ----------
mkdir -p "$ACME_HOME/dnsapi"
[ ! -f "$ACME_HOME/dnsapi/dns_cf.sh" ] && wget -qO "$ACME_HOME/dnsapi/dns_cf.sh" https://raw.githubusercontent.com/acmesh-official/acme.sh/master/dnsapi/dns_cf.sh && chmod +x "$ACME_HOME/dnsapi/dns_cf.sh"

# ---------- Register ACME account ----------
echo -e "[${green}INFO${nc}] Registering ACME account..."
retry bash "$ACME_HOME/acme.sh" --register-account -m ssl@ipgivpn.my.id --server letsencrypt

# ---------- Issue wildcard certificate ----------
echo -e "[${blue}INFO${nc}] Issuing wildcard certificate for ${domain}..."
retry bash "$ACME_HOME/acme.sh" --issue --dns dns_cf -d "$domain" -d "*.$domain" --force --server letsencrypt

# ---------- Install certificate ----------
echo -e "[${blue}INFO${nc}] Installing certificate..."
mkdir -p /usr/local/etc/xray
retry bash "$ACME_HOME/acme.sh" --installcert -d "$domain" \
  --fullchainpath /usr/local/etc/xray/xray.crt \
  --keypath /usr/local/etc/xray/xray.key

# ---------- Auto-renew cron ----------
cat > /etc/cron.d/acme-renew <<EOF
0 3 1 */2 * root $ACME_HOME/acme.sh --cron --home $ACME_HOME > /var/log/acme-renew.log 2>&1
EOF
chmod 644 /etc/cron.d/acme-renew

# ---------- Done ----------
echo -e "[${green}SUCCESS${nc}] ACME.sh + Cloudflare setup completed!"
echo -e "CRT: /usr/local/etc/xray/xray.crt"
echo -e "KEY: /usr/local/etc/xray/xray.key"

# Auto-detect Xray SSL and convert
XRAY_DIR="/usr/local/etc/xray"
# Cari file SSL Xray
CERT=$(find $XRAY_DIR -name "*.crt" -o -name "*.pem" -o -name "fullchain.cer" | head -1)
KEY=$(find $XRAY_DIR -name "*.key" -o -name "private.key" | head -1)

mkdir -p /etc/stunnel
# convert from xray
if [ -f "$CERT" ] && [ -f "$KEY" ]; then
cat "$CERT" "$KEY" > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem
echo "✅ SSL converted from Xray"
else
# make a certificate
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 3650 \
-subj "/C=ID/ST=Jakarta/L=Jakarta/O=givps/OU=IT/CN=localhost/emailAddress=admin@localhost"
cat key.pem cert.pem > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem
echo "✅ Use Self-signed SSL"
fi

uuid=$(cat /proc/sys/kernel/random/uuid)
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$uuid" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless" }
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan-ws" }
      }
    },
    {
      "tag": "ss-ws",
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "password": "$uuid"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/ss-ws" }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$uuid" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "vless-grpc" }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10006,
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "vmess-grpc" }
      }
    },
    {
      "tag": "trojan-grpc",
      "listen": "127.0.0.1",
      "port": 10007,
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "$uuid" }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "trojan-grpc" }
      }
    },
    {
      "tag": "ss-grpc",
      "listen": "127.0.0.1",
      "port": 10008,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "password": "$uuid"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": { "serviceName": "ss-grpc" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl start xray

# nginx
cat > /etc/nginx/conf.d/xray.conf <<'EOF'
server {
    listen 127.0.0.1:8080;
    server_name _;

    location /vless {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /vmess {
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /trojan-ws {
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /ss-ws {
        proxy_pass http://127.0.0.1:10004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }
}

server {
    listen 127.0.0.1:4433 ssl http2;
    server_name _;

    ssl_certificate /usr/local/etc/xray/xray.crt;
    ssl_certificate_key /usr/local/etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_conf_command Ciphersuites TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;
    ssl_stapling off;
    ssl_stapling_verify off;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    location /vless {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /vmess {
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /trojan-ws {
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /ss-ws {
        proxy_pass http://127.0.0.1:10004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache_bypass $http_upgrade;
        proxy_intercept_errors off;
        keepalive_timeout 120s;
        tcp_nodelay on;
        tcp_nopush on;
    }

    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:10005;
        client_max_body_size 0;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        keepalive_timeout 120s;
        proxy_buffering off;
    }

    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:10006;
        client_max_body_size 0;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        keepalive_timeout 120s;
        proxy_buffering off;
    }

    location /trojan-grpc {
        grpc_pass grpc://127.0.0.1:10007;
        client_max_body_size 0;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        keepalive_timeout 120s;
        proxy_buffering off;
    }

    location /ss-grpc {
        grpc_pass grpc://127.0.0.1:10008;
        client_max_body_size 0;
        grpc_set_header X-Real-IP $remote_addr;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
        grpc_read_timeout 86400s;
        grpc_send_timeout 86400s;
        keepalive_timeout 120s;
        proxy_buffering off;
    }
}
EOF

# Reload systemd and start Xray
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

cd /usr/bin
# vless
wget -O add-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/add-vless.sh" && chmod +x add-vless
wget -O trial-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/trial-vless.sh" && chmod +x trial-vless
wget -O renew-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/renew-vless.sh" && chmod +x renew-vless
wget -O del-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/del-vless.sh" && chmod +x del-vless
wget -O cek-vless "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/cek-vless.sh" && chmod +x cek-vless
# vmess
wget -O add-ws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/add-ws.sh" && chmod +x add-ws
wget -O trial-vmess "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/trial-vmess.sh" && chmod +x trial-vmess
wget -O renew-ws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/renew-ws.sh" && chmod +x renew-ws
wget -O del-ws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/del-ws.sh" && chmod +x del-ws
wget -O cek-ws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/cek-ws.sh" && chmod +x cek-ws

# trojan
wget -O add-tr "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/add-tr.sh" && chmod +x add-tr
wget -O trial-trojan "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/trial-trojan.sh" && chmod +x trial-trojan
wget -O renew-tr "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/renew-tr.sh" && chmod +x renew-tr
wget -O del-tr "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/del-tr.sh" && chmod +x del-tr
wget -O cek-tr "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/cek-tr.sh" && chmod +x cek-tr

# shadowsocks
wget -O add-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/add-ssws.sh" && chmod +x add-ssws
wget -O trial-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/trial-ssws.sh" && chmod +x trial-ssws
wget -O renew-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/renew-ssws.sh" && chmod +x renew-ssws
wget -O del-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/del-ssws.sh" && chmod +x del-ssws
wget -O cek-ssws "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/cek-ssws.sh" && chmod +x cek-ssws

# xray acces & error log
wget -O xray-log "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/xray-log.sh" && chmod +x xray-log
