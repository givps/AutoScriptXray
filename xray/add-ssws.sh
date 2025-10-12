#!/bin/bash
# =========================================
# add shadowsock
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

# ==========================================
# Getting system info
MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || cat /root/domain 2>/dev/null)

# Validate domain exists
if [[ -z "$domain" ]]; then
    echo -e "${red}ERROR${nc}: Domain not found. Please set domain first."
    exit 1
fi

# Get ports from log
tls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS TLS" | cut -d: -f2 | sed 's/ //g')"
ntls="$(cat ~/log-install.txt 2>/dev/null | grep -w "Shadowsocks WS none TLS" | cut -d: -f2 | sed 's/ //g')"

# Validate ports
if [[ -z "$tls" ]] || [[ -z "$ntls" ]]; then
    echo -e "${red}ERROR${nc}: Could not find Shadowsocks ports in log file."
    exit 1
fi

# Function to validate username
validate_username() {
    local user="$1"
    if [[ ! $user =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}ERROR${nc}: Username can only contain letters, numbers and underscores"
        return 1
    fi
    
    local client_exists=$(grep -w "$user" /usr/local/etc/xray/config.json 2>/dev/null | wc -l)
    if [[ $client_exists -gt 0 ]]; then
        echo -e "${red}ERROR${nc}: User $user already exists"
        return 1
    fi
    
    return 0
}

# Main user input loop
while true; do
    echo -e "${red}=========================================${nc}"
    echo -e "${blue}      Add Shadowsocks Account    ${nc}"
    echo -e "${red}=========================================${nc}"
    echo -e "${yellow}Info: Username must contain only letters, numbers, underscores${nc}"
    echo ""
    
    read -rp "Username: " user
    
    if validate_username "$user"; then
        break
    fi
    
    echo ""
    echo -e "${red}Please choose a different username${nc}"
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    clear
done

# Cipher and UUID
cipher="aes-128-gcm"
uuid=$(cat /proc/sys/kernel/random/uuid)

# Get expiry date with validation
while true; do
    read -p "Expired (days): " masaaktif
    if [[ $masaaktif =~ ^[0-9]+$ ]] && [ $masaaktif -gt 0 ]; then
        break
    else
        echo -e "${red}ERROR${nc}: Please enter a valid number of days"
    fi
done

exp=$(date -d "$masaaktif days" +"%Y-%m-%d")

# Backup config file before modification
cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Add user to config.json
if ! sed -i '/#ssws$/a\### '"$user $exp"'\
},{"password": "'"$uuid"'","method": "'"$cipher"'","email": "'"$user"'"' /usr/local/etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json"
    exit 1
fi

if ! sed -i '/#ssgrpc$/a\### '"$user $exp"'\
},{"password": "'"$uuid"'","method": "'"$cipher"'","email": "'"$user"'"' /usr/local/etc/xray/config.json; then
    echo -e "${red}ERROR${nc}: Failed to update config.json for gRPC"
    # Restore backup on error
    cp /usr/local/etc/xray/config.json.backup.* /usr/local/etc/xray/config.json 2>/dev/null
    exit 1
fi

# Create shadowsocks links
echo "$cipher:$uuid" > /tmp/log
shadowsocks_base64=$(cat /tmp/log)
echo -n "${shadowsocks_base64}" | base64 > /tmp/log1
shadowsocks_base64e=$(cat /tmp/log1)

shadowsockslink="ss://${shadowsocks_base64e}@bug.com:$tls?path=ss-ws&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
shadowsockslink1="ss://${shadowsocks_base64e}@bug.com:$ntls?path=ss-ws&security=none&host=${domain}&type=ws#${user}"
shadowsockslink2="ss://${shadowsocks_base64e}@${domain}:$tls?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni=bug.com#${user}"

# Restart services
if ! systemctl restart xray; then
    echo -e "${red}ERROR${nc}: Failed to restart Xray service"
    exit 1
fi

# Cleanup temp files
rm -rf /tmp/log /tmp/log1

# Create client config file
CLIENT_DIR="/home/vps/public_html"
mkdir -p "$CLIENT_DIR"

cat > "$CLIENT_DIR/ss-$user.txt" <<-END
# ==========================================
# Shadowsocks Client Configuration
# Generated: $(date)
# Username: $user
# Expiry: $exp
# ==========================================

# Shadowsocks WS TLS Configuration
{
 "dns": {
    "servers": ["1.1.1.1", "9.9.9.9"]
  },
 "inbounds": [
   {
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 8
      },
      "sniffing": {
        "destOverride": ["http", "tls"],
        "enabled": true
      },
      "tag": "socks"
    },
    {
      "port": 10809,
      "protocol": "http",
      "settings": {"userLevel": 8},
      "tag": "http"
    }
  ],
  "log": {"loglevel": "none"},
  "outbounds": [
    {
      "mux": {"enabled": true},
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "$domain",
            "level": 8,
            "method": "$cipher",
            "password": "$uuid",
            "port": 443
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true,
          "serverName": "bug.com"
        },
        "wsSettings": {
          "headers": {"Host": "$domain"},
          "path": "/ss-ws"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {"response": {"type": "http"}},
      "tag": "block"
    }
  ],
  "policy": {
    "levels": {
      "8": {
        "connIdle": 300,
        "downlinkOnly": 1,
        "handshake": 4,
        "uplinkOnly": 1
      }
    },
    "system": {
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "Asls",
    "rules": []
  },
  "stats": {}
}

# ==========================================

# Shadowsocks gRPC Configuration
{
    "dns": {
    "servers": ["1.1.1.1", "9.9.9.9"]
  },
 "inbounds": [
   {
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 8
      },
      "sniffing": {
        "destOverride": ["http", "tls"],
        "enabled": true
      },
      "tag": "socks"
    },
    {
      "port": 10809,
      "protocol": "http",
      "settings": {"userLevel": 8},
      "tag": "http"
    }
  ],
  "log": {"loglevel": "none"},
  "outbounds": [
    {
      "mux": {"enabled": true},
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "$domain",
            "level": 8,
            "method": "$cipher",
            "password": "$uuid",
            "port": 443
          }
        ]
      },
      "streamSettings": {
        "grpcSettings": {
          "multiMode": true,
          "serviceName": "ss-grpc"
        },
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true,
          "serverName": "bug.com"
        }
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {"response": {"type": "http"}},
      "tag": "block"
    }
  ],
  "policy": {
    "levels": {
      "8": {
        "connIdle": 300,
        "downlinkOnly": 1,
        "handshake": 4,
        "uplinkOnly": 1
      }
    },
    "system": {
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "Asls",
    "rules": []
  },
  "stats": {}
}
END

# Restart services quietly
systemctl restart xray > /dev/null 2>&1
service cron restart > /dev/null 2>&1

# Display results
clear
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${blue}        Shadowsocks Account      ${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Remarks        : ${user}" | tee -a /var/log/create-shadowsocks.log
echo -e "IP             : ${MYIP}" | tee -a /var/log/create-shadowsocks.log
echo -e "Domain         : ${domain}" | tee -a /var/log/create-shadowsocks.log
echo -e "Wildcard       : bug.com.${domain}" | tee -a /var/log/create-shadowsocks.log
echo -e "Port TLS       : ${tls}" | tee -a /var/log/create-shadowsocks.log
echo -e "Port none TLS  : ${ntls}" | tee -a /var/log/create-shadowsocks.log
echo -e "Port gRPC      : ${tls}" | tee -a /var/log/create-shadowsocks.log
echo -e "Password       : ${uuid}" | tee -a /var/log/create-shadowsocks.log
echo -e "Ciphers        : ${cipher}" | tee -a /var/log/create-shadowsocks.log
echo -e "Network        : ws/grpc" | tee -a /var/log/create-shadowsocks.log
echo -e "Path           : /ss-ws" | tee -a /var/log/create-shadowsocks.log
echo -e "ServiceName    : ss-grpc" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Link TLS       : ${shadowsockslink}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Link none TLS  : ${shadowsockslink1}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Link gRPC      : ${shadowsockslink2}" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo -e "Expired On     : $exp" | tee -a /var/log/create-shadowsocks.log
echo -e "Config File    : $CLIENT_DIR/ss-$user.txt" | tee -a /var/log/create-shadowsocks.log
echo -e "${red}=========================================${nc}" | tee -a /var/log/create-shadowsocks.log
echo "" | tee -a /var/log/create-shadowsocks.log

read -n 1 -s -r -p "Press any key to back on menu"
m-ssws
