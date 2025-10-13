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

# Install all packages in one command (more efficient)
echo -e "[ ${green}INFO${nc} ] Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y \
    iptables iptables-persistent \
    curl python3 socat xz-utils wget apt-transport-https \
    gnupg gnupg2 gnupg1 dnsutils lsb-release \
    cron bash-completion \
    zip pwgen openssl netcat

# Clean up packages
echo -e "[ ${green}INFO${nc} ] Cleaning up..."
apt clean all && apt autoremove -y

# install xray
echo -e "[ ${green}INFO${nc} ] Downloading & Installing xray core"
# Create directory if doesn't exist and set permissions
echo -e "[ INFO ] Creating directories and setting permissions..."
mkdir -p /usr/local/etc/xray /var/log/xray /home/vps/public_html /run/xray
# Set ownership recursive untuk config dan log
chown -R www-data:www-data /usr/local/etc/xray /var/log/xray /run/xray
# Set permissions
chmod 755 /var/log/xray /run/xray
chmod 750 /usr/local/etc/xray
# Create log files
touch /var/log/xray/access.log /var/log/xray/error.log
chmod 644 /var/log/xray/access.log /var/log/xray/error.log
echo -e "[ INFO ] Directory setup completed"

# xray official
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data

# nginx stop
systemctl stop nginx

LOG_FILE="/var/log/acme-setup.log"
mkdir -p /var/log
rm -rf /root/.acme.sh
rm -f /usr/local/etc/xray/{xray.crt,xray.key}
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
DEFAULT_CF_TOKEN="GxfBrA3Ez39MdJo53EV-LiC4dM1-xn5rslR-m5Ru"
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
retry bash "$ACME_HOME/acme.sh" --register-account -m ssl@givps.com --server letsencrypt

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

# generate uuid
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
          {
            "id": "$uuid",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless"
        }
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan-ws"
        }
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
        "security": "none",
        "wsSettings": {
          "path": "/ss-ws"
        }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    },
    {
      "tag": "vmess-grpc",
      "listen": "127.0.0.1",
      "port": 10006,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },
    {
      "tag": "trojan-grpc",
      "listen": "127.0.0.1",
      "port": 10007,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "trojan-grpc"
        }
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
        "security": "none",
        "grpcSettings": {
          "serviceName": "ss-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
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
User=www-data
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

cat > /etc/systemd/system/run.service <<EOF
[Unit]
Description=Xray Runtime Directory Service
After=network.target

[Service]
Type=simple
ExecStartPre=-/usr/bin/mkdir -p /var/run/xray
ExecStart=/usr/bin/chown www-data:www-data /var/run/xray
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

#nginx config
cat > /etc/nginx/conf.d/xray.conf <<EOF
# /etc/nginx/conf.d/xray.conf
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $domain;
    
    # SSL Configuration
    ssl_certificate /usr/local/etc/xray/xray.crt;
    ssl_certificate_key /usr/local/etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # gRPC Settings (tanpa http2 directive)
    client_max_body_size 0;
    grpc_read_timeout 1h;
    grpc_send_timeout 1h;
    
    # gRPC Locations
    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:10005;
    }
    
    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:10006;
    }
    
    location /trojan-grpc {
        grpc_pass grpc://127.0.0.1:10007;
    }
    
    location /ss-grpc {
        grpc_pass grpc://127.0.0.1:10008;
    }
    
    # WebSocket Locations
    location /vless {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
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
    }
    
    # Default response
    location / {
        return 404;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://$server_name$request_uri;
}
EOF

# enable services
systemctl enable xray.service
systemctl enable run.service
systemctl enable nginx

# reload
systemctl daemon-reload

# start
systemctl start cron
systemctl start xray.service
systemctl start run.service
systemctl start nginx

# restart
systemctl restart cron
systemctl restart xray.service
systemctl restart run.service
systemctl restart nginx

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
