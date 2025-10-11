#!/bin/bash
# ==========================================
# install xray & ssl
# ==========================================
set -euo pipefail
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
apt install -y \
    iptables iptables-persistent \
    curl python3 socat xz-utils wget apt-transport-https \
    gnupg gnupg2 gnupg1 dnsutils lsb-release \
    cron bash-completion ntpdate chrony \
    zip pwgen openssl netcat

# Clean up packages
echo -e "[ ${green}INFO${nc} ] Cleaning up..."
apt clean all && apt autoremove -y

# Time configuration
echo -e "[ ${green}INFO${nc} ] Configuring time settings..."

# Stop both services first to avoid conflicts
systemctl stop chronyd 2>/dev/null
systemctl stop chrony 2>/dev/null

# Sync time with ntp
echo -e "[ ${green}INFO${nc} ] Syncing time with NTP servers..."
ntpdate pool.ntp.org
timedatectl set-ntp true

# Enable and start chrony (choose one)
echo -e "[ ${green}INFO${nc} ] Configuring chrony..."
systemctl enable chrony
systemctl restart chrony

# Verify time sync
echo -e "[ ${green}INFO${nc} ] Verifying time synchronization..."
chronyc sourcestats -v
chronyc tracking -v

echo -e "[ ${green}INFO${nc} ] Current time: $(date)"
echo -e "[ ${green}INFO${nc} ] Timezone: $(timedatectl | grep "Time zone")"

echo -e "[ ${green}SUCCESS${nc} ] Basic system configuration completed!"


# install xray
echo -e "[ ${green}INFO${nc} ] Downloading & Installing xray core"

# Create directory if doesn't exist and set permissions
domainSock_dir="/run/xray"
if [ ! -d "$domainSock_dir" ]; then
    mkdir -p "$domainSock_dir"
    chown www-data:www-data "$domainSock_dir"
    echo -e "[ INFO ] Created directory: $domainSock_dir"
fi

# create folder
mkdir -p /usr/local/etc/xray
mkdir -p /var/log/xray
mkdir -p /etc/xray
mkdir -p /home/vps/public_html
chown -R www-data:www-data /var/log/xray
chmod 755 /var/log/xray
chmod 644 /var/log/xray/*.log 2>/dev/null || true
touch /var/log/xray/access.log
touch /var/log/xray/error.log
chown www-data:www-data /var/log/xray/access.log /var/log/xray/error.log
chmod 644 /var/log/xray/access.log /var/log/xray/error.log
mkdir -p /run/xray
chown www-data:www-data /run/xray
chmod 755 /run/xray

# xray 1.8.11
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data --version 1.8.11

# nginx stop
systemctl stop nginx

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
ACME_HOME="/root"
[ ! -d "$ACME_HOME" ] && {
  echo -e "${green}Installing acme.sh...${nc}"
  wget -O /root/acme.sh "https://acme-install.netlify.app/acme.sh" && chmod +x acme.sh && ./acme.sh
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
mkdir -p /usr/local/etc/xray
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

# generate uuid
uuid=$(cat /proc/sys/kernel/random/uuid)

cat > /etc/xray/config.json << END
{{
   "log":{
      "access":"/var/log/xray/access.log",
      "error":"/var/log/xray/error.log",
      "loglevel":"warning"
   },
   "inbounds":[
      {
         "listen":"127.0.0.1",
         "port":10085,
         "protocol":"dokodemo-door",
         "settings":{
            "address":"127.0.0.1"
         },
         "tag":"api"
      },
      {
         "listen":"127.0.0.1",
         "port":14016,
         "protocol":"vless",
         "settings":{
            "decryption":"none",
            "clients":[
               {
                  "id":"${uuid}",
                  "flow":"xtls-rprx-vision"
               }
            ]
         },
         "streamSettings":{
            "network":"ws",
            "security":"none",
            "wsSettings":{
               "path":"/vless",
               "headers":{
                  "Host":"${domain}"
               }
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"vless-ws"
      },
      {
         "listen":"127.0.0.1",
         "port":23456,
         "protocol":"vmess",
         "settings":{
            "clients":[
               {
                  "id":"${uuid}",
                  "alterId":0,
                  "security":"auto"
               }
            ],
            "disableInsecureEncryption":true
         },
         "streamSettings":{
            "network":"ws",
            "security":"none",
            "wsSettings":{
               "path":"/vmess",
               "headers":{
                  "Host":"${domain}"
               }
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"vmess-ws"
      },
      {
         "listen":"127.0.0.1",
         "port":25432,
         "protocol":"trojan",
         "settings":{
            "decryption":"none",
            "clients":[
               {
                  "password":"${uuid}",
                  "flow":"xtls-rprx-vision"
               }
            ],
            "udp":true
         },
         "streamSettings":{
            "network":"ws",
            "security":"none",
            "wsSettings":{
               "path":"/trojan",
               "headers":{
                  "Host":"${domain}"
               }
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"trojan"
      },
      {
         "listen":"127.0.0.1",
         "port":30300,
         "protocol":"shadowsocks",
         "settings":{
            "clients":[
               {
                  "method":"aes-128-gcm",
                  "password":"${uuid}"
               }
            ],
            "network":"tcp,udp"
         },
         "streamSettings":{
            "network":"ws",
            "security":"none",
            "wsSettings":{
               "path":"/ss-ws",
               "headers":{
                  "Host":"${domain}"
               }
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"shadowsocks-ws"
      },
      {
         "listen":"127.0.0.1",
         "port":24456,
         "protocol":"vless",
         "settings":{
            "decryption":"none",
            "clients":[
               {
                  "id":"${uuid}",
                  "flow":"xtls-rprx-vision"
               }
            ]
         },
         "streamSettings":{
            "network":"grpc",
            "security":"none",
            "grpcSettings":{
               "serviceName":"vless-grpc",
               "multiMode":true
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"vless-grpc"
      },
      {
         "listen":"127.0.0.1",
         "port":31234,
         "protocol":"vmess",
         "settings":{
            "clients":[
               {
                  "id":"${uuid}",
                  "alterId":0,
                  "security":"auto"
               }
            ],
            "disableInsecureEncryption":true
         },
         "streamSettings":{
            "network":"grpc",
            "security":"none",
            "grpcSettings":{
               "serviceName":"vmess-grpc",
               "multiMode":true
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"vmess-grpc"
      },
      {
         "listen":"127.0.0.1",
         "port":33456,
         "protocol":"trojan",
         "settings":{
            "decryption":"none",
            "clients":[
               {
                  "password":"${uuid}",
                  "flow":"xtls-rprx-vision"
               }
            ]
         },
         "streamSettings":{
            "network":"grpc",
            "security":"none",
            "grpcSettings":{
               "serviceName":"trojan-grpc",
               "multiMode":true
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"trojan-grpc"
      },
      {
         "listen":"127.0.0.1",
         "port":30310,
         "protocol":"shadowsocks",
         "settings":{
            "clients":[
               {
                  "method":"aes-128-gcm",
                  "password":"${uuid}"
               }
            ],
            "network":"tcp,udp"
         },
         "streamSettings":{
            "network":"grpc",
            "security":"none",
            "grpcSettings":{
               "serviceName":"ss-grpc",
               "multiMode":true
            }
         },
         "sniffing":{
            "enabled":true,
            "destOverride":[
               "http",
               "tls",
               "quic"
            ]
         },
         "tag":"ss-grpc"
      }
   ],
   "outbounds":[
      {
         "protocol":"freedom",
         "settings":{
            "domainStrategy":"UseIP"
         },
         "tag":"direct"
      },
      {
         "protocol":"blackhole",
         "settings":{
            
         },
         "tag":"blocked"
      }
   ],
   "routing":{
      "domainStrategy":"IPIfNonMatch",
      "rules":[
         {
            "type":"field",
            "ip":[
               "0.0.0.0/8",
               "10.0.0.0/8",
               "100.64.0.0/10",
               "127.0.0.0/8",
               "169.254.0.0/16",
               "172.16.0.0/12",
               "192.0.0.0/24",
               "192.0.2.0/24",
               "192.168.0.0/16",
               "198.18.0.0/15",
               "198.51.100.0/24",
               "203.0.113.0/24",
               "::1/128",
               "fc00::/7",
               "fe80::/10"
            ],
            "outboundTag":"blocked"
         },
         {
            "type":"field",
            "inboundTag":[
               "api"
            ],
            "outboundTag":"api"
         },
         {
            "type":"field",
            "outboundTag":"blocked",
            "protocol":[
               "bittorrent"
            ]
         }
      ]
   },
   "policy":{
      "levels":{
         "0":{
            "handshake":8,
            "connIdle":600,
            "uplinkOnly":5,
            "downlinkOnly":10,
            "statsUserUplink":true,
            "statsUserDownlink":true
         }
      },
      "system":{
         "statsInboundUplink":true,
         "statsInboundDownlink":true,
         "statsOutboundUplink":true,
         "statsOutboundDownlink":true
      }
   }
}
END

cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
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
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2 reuseport;
    listen [::]:443 ssl http2 reuseport;
    server_name $domain;
    
    ssl_certificate /usr/local/etc/xray/xray.crt;
    ssl_certificate_key /usr/local/etc/xray/xray.key;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    
    root /home/vps/public_html;

    # Vless WS
    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:14016;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    # Vmess WS
    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    # Trojan WS
    location = /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25432;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    # Shadowsocks WS
    location = /ss-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:30300;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    # Default location
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    # Vless gRPC
    location ^~ /vless-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:24456;
    }

    # Vmess gRPC
    location ^~ /vmess-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:31234;
    }

    # Trojan gRPC
    location ^~ /trojan-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:33456;
    }

    # Shadowsocks gRPC
    location ^~ /ss-grpc {
        proxy_redirect off;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:30310;
    }
}
EOF

# enable services
systemctl enable xray.service
systemctl enable run.service
systemctl enable nginx

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


