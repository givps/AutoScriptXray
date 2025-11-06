# (MUST READ) before install

<h2 align="center">Supported Linux Distributions</h2>

<p align="center">
  <img src="https://d33wubrfki0l68.cloudfront.net/5911c43be3b1da526ed609e9c55783d9d0f6b066/9858b/assets/img/debian-ubuntu-hover.png" alt="Debian and Ubuntu" style="max-width:100%; height:auto;">
</p>

<p align="center">
  <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2011&message=Bullseye&color=purple" alt="Debian 11 Bullseye">
  <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2012&message=Bookworm&color=purple" alt="Debian 12 Bookworm">
  <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2018.04&message=LTS&color=red" alt="Ubuntu 18.04 LTS">
  <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2020.04&message=LTS&color=red" alt="Ubuntu 20.04 LTS">
</p>

-----------------------------------------------------------------------------------------

# Required VPS is still fresh (MUST) / have never installed anything
<br>
- If you install the Script twice, you need to rebuild the VPS to factory settings, in the VPS provider panel<br>
- DOMAIN (MUST) / Random from Script<br>
- DEBIAN 11/12 or later<br>
- Ubuntu 18/20 LTS or later<br>
- CPU MIN 1 CORE<br>
- RAM 1GB<br>
<br>

-----------------------------------------------------------------------------------------

# Cloudflare setting for those who have their own Domain, you can check at folder [image](https://github.com/givps/AutoScriptXray/blob/master/image/README.md) to display other setting or use your API Token auto record with own your Domain [API](https://github.com/givps/AutoScriptXray/blob/master/cloudflare/api-token/README.md)
<br>
- SSL/TLS : FULL<br>
- SSL/TLS Recommender : OFF<br>
- GRPC : ON<br>
- WEBSOCKET : ON<br>
- Always Use HTTPS : OFF<br>
- UNDER ATTACK MODE : OFF<br>
<br>

# Pointing
![Pointing](https://raw.githubusercontent.com/givps/AutoScriptXray/master/image/pointing.png)

-----------------------------------------------------------------------------------------

# Stunnel Version with Tor install
- Step 1 for (debian) please update first
```
apt update && apt upgrade -y && apt autoremove -y && reboot
```
- Step 2 for (ubuntu) directly install
```
apt update && apt install -y bzip2 gzip coreutils screen curl unzip && wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/setup.sh && chmod +x setup.sh && sed -i -e 's/\r$//' setup.sh && screen -S setup ./setup.sh
```
# Stunnel Version Port :
<br>
- OpenSSH                  : 22, 2222<br>
- Dropbear                 : 109, 110<br>
- SSH SSL Websocket        : 444, 1444<br>
- SSH Websocket            : 80, 1445<br>
- Stunnel4                 : 222, 333, 777<br>
- Badvpn                   : 7100-7900<br>
- OpenVPN                  : 443, 1195, 51825<br>
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

-----------------------------------------------------------------------------------------

# HAProxy Version install
- Step 1 for (debian) update first
```
apt update && apt upgrade -y && apt autoremove -y && reboot
```
- Step 2 for (ubuntu) directly install
```
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 && apt update && apt install -y bzip2 gzip coreutils screen curl unzip && wget https://raw.githubusercontent.com/givps/AutoScriptXray/master/haproxy/setup/setup.sh && chmod +x setup.sh && sed -i -e 's/\r$//' setup.sh && screen -S setup ./setup.sh
```
# HAProxy Version Port :
<br>
- OpenSSH                  : 22, 2222<br>
- SSH/SSL HAProxy          : 1445, 1446<br>
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

-----------------------------------------------------------------------------------------

<p align="left">
  <a href="https://t.me/givps_com"><img src="https://img.shields.io/badge/Telegram-blue" alt="Telegram"></a>
</p>

<p align="left">
  <a href="#"><img src="https://img.shields.io/badge/Donate-green" alt="Donate"></a>
  <a href="https://www.blockchain.com/explorer/addresses/eth/0xa7431b95bbd425303812b610626a4e784551cdab"><img src="https://img.shields.io/badge/allEVM-white" alt="allEVM"></a>
  <a href="https://ko-fi.com/givps"><img src="https://img.shields.io/badge/Ko--fi-orange" alt="Ko-fi"></a>
  <a href="https://trakteer.id/givps/tip"><img src="https://img.shields.io/badge/Trakteer-red" alt="Trakteer"></a>
</p>

-----------------------------------------------------------------------------------------

⚠️ ATTENTION (MUST READ CAREFULLY)

🚫 Not for Sale — This script is distributed free of charge. Selling it is strictly prohibited.

🔒 Data & Privacy Disclaimer — Your internet usage history and data security are your own responsibility.
The script provider does not store or track any of your activity.

🌐 Network Monitoring — All your traffic and logs are managed by your VPS provider and possibly government agencies (e.g., FBI).

⚙️ Use Responsibly — Use this script wisely to avoid legal or ethical problems.

-----------------------------------------------------------------------------------------

🧾 FINAL MESSAGE

🙏 Thank you for taking the time to read this notice.

💬 Apologies if any words sound harsh — I am human and not free from mistakes.

🐞 Found a bug...? Please report it here → [GitHub Issues](https://github.com/givps/AutoScriptXray/issues)

-----------------------------------------------------------------------------------------

<p align="left">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="#"><img src="https://img.shields.io/badge/Auto_Script_VPS-blue" alt="Auto Script VPS"></a>
</p>

-----------------------------------------------------------------------------------------


