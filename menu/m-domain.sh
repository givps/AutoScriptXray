#!/bin/bash
# =========================================
# CHANGE DOMAIN VPS WITH DNS CHECK & AUTO RENEW SSL
# =========================================

# Color
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
nc='\e[0m'

MYIP=$(wget -qO- ipv4.icanhazip.com || curl -s ifconfig.me)
clear
echo -e "${red}=========================================${nc}"
echo -e "${green}     CUSTOM SETUP DOMAIN VPS     ${nc}"
echo -e "${red}=========================================${nc}"
echo -e "${white}1${nc} Use Domain From Script"
echo -e "${white}2${nc} Choose Your Own Domain"
echo -e "${red}=========================================${nc}"
read -rp "Choose Your Domain Installation 1/2 : " dom 

if [[ $dom -eq 1 ]]; then
    clear
    rm -f /root/cf.sh
    wget -q -O /root/cf.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/ssh/cf.sh"
    chmod +x /root/cf.sh && bash /root/cf.sh
    rm -f /root/crt.sh
    wget -q -O /root/crt.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/crt.sh"
    chmod +x /root/crt.sh && bash /root/crt.sh
    #rm -f /root/slowdns.sh
    #wget -q -O /root/slowdns.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/slowdns/slowdns.sh"
    #chmod +x /root/slowdns.sh && bash /root/slowdns.sh

elif [[ $dom -eq 2 ]]; then
    read -rp "Enter Your Domain : " domen
    rm -f /usr/local/etc/xray/domain /root/domain
    echo "$domen" | tee /usr/local/etc/xray/domain /root/domain >/dev/null

    echo -e "\n${yellow}Checking DNS record for ${domen}...${nc}"
    DNS_IP=$(dig +short A "$domen" @1.1.1.1 | head -n1)

    if [[ -z "$DNS_IP" ]]; then
        echo -e "${red}No DNS record found for ${domen}.${nc}"
    elif [[ "$DNS_IP" != "$MYIP" ]]; then
        echo -e "${yellow}⚠ Domain does not point to this VPS.${nc}"
        echo -e "Your VPS IP: ${green}$MYIP${nc}"
        echo -e "Current DNS IP: ${red}$DNS_IP${nc}"
    else
        echo -e "${green}✅ Domain already points to this VPS.${nc}"
    fi

    # If not pointing, offer Cloudflare API creation
    if [[ "$DNS_IP" != "$MYIP" ]]; then
        echo -e "\n${yellow}Would you like to create an A record on Cloudflare using API Token?${nc}"
        read -rp "Create record automatically? (y/n): " ans
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
            read -rp "Enter your Cloudflare API Token: " CF_API
            read -rp "Enter your Cloudflare Zone Name / Primary Domain Name (e.g. example.com): " CF_ZONE
            ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_ZONE}" \
                -H "Authorization: Bearer ${CF_API}" \
                -H "Content-Type: application/json" | jq -r '.result[0].id')

            if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
                echo -e "${red}Failed to get Zone ID. Please check your token and zone name.${nc}"
            else
                echo -e "${green}Zone ID found: ${ZONE_ID}${nc}"
                # Create or update DNS record
                RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${domen}" \
                    -H "Authorization: Bearer ${CF_API}" \
                    -H "Content-Type: application/json" | jq -r '.result[0].id')

                if [[ "$RECORD_ID" == "null" || -z "$RECORD_ID" ]]; then
                    echo -e "${yellow}Creating new A record for ${domen}...${nc}"
                    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
                        -H "Authorization: Bearer ${CF_API}" \
                        -H "Content-Type: application/json" \
                        --data "{\"type\":\"A\",\"name\":\"${domen}\",\"content\":\"${MYIP}\",\"ttl\":120,\"proxied\":false}" >/dev/null
                else
                    echo -e "${yellow}Updating existing A record for ${domen}...${nc}"
                    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
                        -H "Authorization: Bearer ${CF_API}" \
                        -H "Content-Type: application/json" \
                        --data "{\"type\":\"A\",\"name\":\"${domen}\",\"content\":\"${MYIP}\",\"ttl\":120,\"proxied\":false}" >/dev/null
                fi
                echo -e "${green}✅ DNS record set to ${MYIP}${nc}"
            fi
        fi
    fi

    # Continue installation
    rm -f /root/crt.sh
    wget -q -O /root/crt.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/xray/crt.sh"
    chmod +x /root/crt.sh && bash /root/crt.sh

    #rm -f /root/slowdns.sh
    #wget -q -O /root/slowdns.sh "https://raw.githubusercontent.com/givps/AutoScriptXray/master/slowdns/slowdns.sh"
    #chmod +x /root/slowdns.sh && bash /root/slowdns.sh

else 
    echo -e "${red}Wrong Argument${nc}"
    exit 1
fi

clear
