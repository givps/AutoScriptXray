#!/bin/bash
# =========================================
# SETUP UDP CUSTOM
# =========================================

# create and delete folder
rm -rf /root/udp
mkdir -p /root/udp
# install udp custom binary
wget -q --show-progress --load-cookies /tmp/cookies.txt "https://github.com/givps/AutoScriptXray/raw/master/udp-custom/udp-custom-linux-amd64" -O /root/udp/udp-custom && rm -rf /tmp/cookies.txt
chmod +x /root/udp/udp-custom

wget -q --show-progress --load-cookies /tmp/cookies.txt "https://github.com/givps/AutoScriptXray/raw/master/udp-custom/config.json" -O /root/udp/config.json && rm -rf /tmp/cookies.txt
chmod 644 /root/udp/config.json

# if need EXCLUDE_ARG="-exclude 53 5300 7100 7200 7300 7400 7500 7600 7700 7800 7900"
SERVICE_FILE="/etc/systemd/system/udp-custom.service"

if [ -z "$1" ]; then
    EXCLUDE_ARG="-exclude 53 5300 7100 7200 7300 7400 7500 7600 7700 7800 7900 8888"
else
    EXCLUDE_ARG="-exclude $1"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ePro Dev. Team
After=network.target

[Service]
User=root
Type=simple
ExecStart=/root/udp/udp-custom server $EXCLUDE_ARG
WorkingDirectory=/root/udp/
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# enable udp-custom
systemctl daemon-reload
systemctl enable udp-custom.service
systemctl start udp-custom.service

