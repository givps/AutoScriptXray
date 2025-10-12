#!/bin/bash
# ==========================================
# install Websocket
# ==========================================

#Install Script Websocket-SSH Python
wget -O /usr/local/bin/ws-dropbear https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/ws-dropbear
wget -O /usr/local/bin/ws-stunnel https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/ws-stunnel
#wget -O /usr/local/bin/ws-ssh https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/ws-ssh

# permision
chmod +x /usr/local/bin/ws-dropbear
chmod +x /usr/local/bin/ws-stunnel
#chmod +x /usr/local/bin/ws-ssh

#System SSH Websocket Dropbear Python
wget -O /etc/systemd/system/ws-dropbear.service https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/ws-dropbear.service && chmod +x /etc/systemd/system/ws-dropbear.service

#System SSH Websocket Stunnel Python
wget -O /etc/systemd/system/ws-stunnel.service https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/ws-stunnel.service && chmod +x /etc/systemd/system/ws-stunnel.service

#System SSH Websocket Python
#wget -O /etc/systemd/system/ws-ssh.service https://raw.githubusercontent.com/givps/AutoScriptXray/master/sshws/ws-ssh.service && chmod +x /etc/systemd/system/ws-ssh.service

#Enable ws-dropbear service
systemctl enable ws-dropbear.service

#Enable ws-openssh service
systemctl enable ws-stunnel.service
