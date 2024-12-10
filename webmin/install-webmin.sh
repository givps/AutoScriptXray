#!/bin/bash
# Quick Setup | Script Setup Manager
# Edition : Stable Edition 1.0
# Author  : givps
# The MIT License (MIT)
# (C) Copyright 2023
# =========================================
# pewarna hidup
BGreen='\e[1;32m'
NC='\e[0m'
cd
clear
rm -rf /usr/bin/m-system
echo -e "\e[1;32m Update Menu System.. \e[0m"
wget -q -O /usr/bin/m-system https://raw.githubusercontent.com/givps/AutoScriptXray/master/webmin/menu/m-system.sh
chmod +x /usr/bin/m-system
rm -rf /usr/bin/wbmn
echo -e "\e[1;32m Start Download Panel Webmin.. \e[0m"
wget -q -O /usr/bin/wbmn https://raw.githubusercontent.com/givps/AutoScriptXray/master/webmin/wbmn.sh
chmod +x /usr/bin/wbmn
#rm -rf /usr/bin/helium
#echo -e "\e[1;32m Start download Panel ADS Block.. \e[0m"
#wget -q -O /usr/bin/helium https://raw.githubusercontent.com/givps/AutoScriptXray/master/helium/helium.sh
#chmod +x /usr/bin/helium
#echo -e "\e[1;32m Setup done Please wait.. \e[0m"
#sleep 2
cd
rm -rf /usr/bin/install-webmin
echo -e "\e[1;32m auto reboot in 5s \e[0m"
sleep 5
reboot

