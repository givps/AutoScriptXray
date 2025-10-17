# [Install]
- Step 1 for (debian) update first
```
apt update && apt upgrade -y && apt autoremove -y && reboot
```
- Step 2 for (ubuntu) directly install
```
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 && apt update && apt install -y bzip2 gzip coreutils screen curl unzip && wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/setup/setup.sh && chmod +x setup.sh && sed -i -e 's/\r$//' setup.sh && screen -S setup ./setup.sh
```
## Service & Port:
<br>
- OpenSSH                  : 22, 2222<br>
- SSH/SSL                  : 1445, 1446<br>
- HAProxy SSH SSL WS       : 1443<br>
- HAProxy SSH WS           : 1444<br>
- Badvpn                   : 7100-7900<br>
- Nginx                    : 80<br>
- Vmess WS TLS             : 443<br>
- Vless WS TLS             : 443<br>
- Trojan WS TLS            : 443<br>
- Shadowsocks WS TLS       : 443<br>
- Vmess WS none TLS        : 80<br>
- Vless WS none TLS        : 80<br>
- Trojan WS none TLS       : 80<br>
- Shadowsocks WS none TLS  : 80<br>
- Vmess gRPC               : 443<br>
- Vless gRPC               : 443<br>
- Trojan gRPC              : 443<br>
- Shadowsocks gRPC         : 443<br>
<br>

# Telegram
[![Telegram](https://img.shields.io/badge/Telegram-blue)](https://t.me/givps_com/)
[![allEVM donate button](https://img.shields.io/badge/Donate-allEVM-blue)](https://www.blockchain.com/explorer/addresses/eth/0xa7431b95bbd425303812b610626a4e784551cdab)

- if you find bug , create a [issues](https://github.com/givps/AutoScriptXray/issues) thx github :)

<p align="center">
<a href="https://opensource.org/licenses/MIT"> <img src="https://img.shields.io/badge/License-MIT-yellow.svg" style="max-width:200%;"> <a><img src="https://img.shields.io/badge/Auto_Script_VPS-HAProxy-blue" style="max-width:200%;">
