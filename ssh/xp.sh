#!/bin/bash
# =========================================
# AUTO DELETE EXPIRED USERS
# =========================================

clear

##----- Auto Remove Vmess
echo "Checking expired Vmess users..."
data=( `cat /etc/xray/config.json | grep '^###' | cut -d ' ' -f 2 | sort | uniq`);
now=`date +"%Y-%m-%d"`
for user in "${data[@]}"
do
exp=$(grep -w "^### $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
d1=$(date -d "$exp" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
if [[ "$exp2" -le "0" ]]; then
echo "Removing expired Vmess user: $user"
sed -i "/^### $user $exp/,/^},{/d" /etc/xray/config.json
rm -f /etc/xray/$user-tls.json /etc/xray/$user-none.json 2>/dev/null
fi
done

#----- Auto Remove Vless
echo "Checking expired Vless users..."
data=( `cat /etc/xray/config.json | grep '^#&' | cut -d ' ' -f 2 | sort | uniq`);
now=`date +"%Y-%m-%d"`
for user in "${data[@]}"
do
exp=$(grep -w "^#& $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
d1=$(date -d "$exp" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
if [[ "$exp2" -le "0" ]]; then
echo "Removing expired Vless user: $user"
sed -i "/^#& $user $exp/,/^},{/d" /etc/xray/config.json
fi
done

#----- Auto Remove Trojan
echo "Checking expired Trojan users..."
data=( `cat /etc/xray/config.json | grep '^#!' | cut -d ' ' -f 2 | sort | uniq`);
now=`date +"%Y-%m-%d"`
for user in "${data[@]}"
do
exp=$(grep -w "^#! $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
d1=$(date -d "$exp" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
if [[ "$exp2" -le "0" ]]; then
echo "Removing expired Trojan user: $user"
sed -i "/^#! $user $exp/,/^},{/d" /etc/xray/config.json
fi
done

#----- Auto Remove Shadowsocks
echo "Checking expired Shadowsocks users..."
# Method 1: Jika menggunakan config.json Xray
if grep -q "shadowsocks" /etc/xray/config.json 2>/dev/null; then
data=( `cat /etc/xray/config.json | grep '"email"' | grep -Eo '[^"@]+@[^"]+' | cut -d@ -f1 | sort | uniq`);
now=`date +"%Y-%m-%d"`
for user in "${data[@]}"
do
if grep -q "\"email\": \"${user}@\"\|${user}@" /etc/xray/config.json; then
exp_line=$(grep -A5 -B5 "\"email\": \"${user}@\"\|${user}@" /etc/xray/config.json | grep -o '"expiry":[0-9]*' | head -1)
if [ -n "$exp_line" ]; then
exp_timestamp=$(echo "$exp_line" | cut -d: -f2)
exp_date=$(date -d "@$exp_timestamp" +"%Y-%m-%d" 2>/dev/null)
if [ -n "$exp_date" ]; then
d1=$(date -d "$exp_date" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
if [[ "$exp2" -le "0" ]]; then
echo "Removing expired Shadowsocks user: $user"
# Hapus berdasarkan email pattern
sed -i "/\"email\": \"${user}@\"/,/},/d" /etc/xray/config.json
fi
fi
fi
done
fi

# Method 2: Jika menggunakan file terpisah untuk Shadowsocks
if [ -f "/etc/shadowsocks/config.json" ]; then
echo "Checking standalone Shadowsocks config..."
data=( `cat /etc/shadowsocks/config.json | grep '"password"' | cut -d'"' -f4 | sort | uniq`);
now=`date +"%Y-%m-%d"`
for user in "${data[@]}"
do
# Cari expiry date (asumsi ada field expiry atau menggunakan created date + duration)
exp_line=$(grep -B10 -A10 "\"password\": \"$user\"" /etc/shadowsocks/config.json | grep -o '"expiry":[0-9]*' | head -1)
if [ -n "$exp_line" ]; then
exp_timestamp=$(echo "$exp_line" | cut -d: -f2)
exp_date=$(date -d "@$exp_timestamp" +"%Y-%m-%d" 2>/dev/null)
if [ -n "$exp_date" ]; then
d1=$(date -d "$exp_date" +%s)
d2=$(date -d "$now" +%s)
exp2=$(( (d1 - d2) / 86400 ))
if [[ "$exp2" -le "0" ]]; then
echo "Removing expired Shadowsocks user: $user"
sed -i "/\"password\": \"$user\"/,/},/d" /etc/shadowsocks/config.json
fi
fi
fi
done
fi

# Restart Xray service jika ada perubahan
if systemctl is-active --quiet xray.service; then
echo "Restarting Xray service..."
systemctl restart xray.service
fi

# Restart Shadowsocks service jika ada
if systemctl is-active --quiet shadowsocks-server 2>/dev/null || systemctl is-active --quiet ss-server 2>/dev/null; then
echo "Restarting Shadowsocks service..."
systemctl restart shadowsocks-server 2>/dev/null || systemctl restart ss-server 2>/dev/null
fi

##------ Auto Remove SSH
echo "Checking expired SSH users..."
hariini=`date +%d-%m-%Y`
cat /etc/shadow | cut -d: -f1,8 | sed /:$/d > /tmp/expirelist.txt
totalaccounts=`cat /tmp/expirelist.txt | wc -l`
deleted_count=0

for((i=1; i<=$totalaccounts; i++ ))
do
tuserval=`head -n $i /tmp/expirelist.txt | tail -n 1`
username=`echo $tuserval | cut -f1 -d:`
userexp=`echo $tuserval | cut -f2 -d:`
userexpireinseconds=$(( $userexp * 86400 ))
tglexp=`date -d @$userexpireinseconds`             
tgl=`echo $tglexp |awk -F" " '{print $3}'`
while [ ${#tgl} -lt 2 ]
do
tgl="0"$tgl
done
while [ ${#username} -lt 15 ]
do
username=$username" " 
done
bulantahun=`echo $tglexp |awk -F" " '{print $2,$6}'`
todaystime=`date +%s`
if [ $userexpireinseconds -ge $todaystime ] ;
then
:
else
echo "Removing expired SSH user: $username"
userdel --force "$username" 2>/dev/null
((deleted_count++))
fi
done

# Cleanup
rm -f /tmp/expirelist.txt

echo "========================================="
echo "Auto cleanup completed!"
echo "Expired users removed: $deleted_count"
echo "Date: $(date)"
echo "========================================="

# Log the activity
echo "[$(date)] Auto cleanup executed. Removed $deleted_count expired users." >> /var/log/auto-cleanup.log
