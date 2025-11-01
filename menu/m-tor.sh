#!/bin/bash
# =====================================
# TOR CONTROL SCRIPT (Enable / Disable)
# =====================================

# Color definitions
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
white='\e[1;37m'
cyan='\e[1;36m'
nc='\e[0m'
if ! id -u debian-tor >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin debian-tor
fi
TOR_UID=$(id -u debian-tor 2>/dev/null || echo 0)

# ---------- FUNCTIONS ----------
enable_tor() {
    echo "== Starting Tor =="
    systemctl start tor

    # Create TOR chain if not exists
    iptables -t nat -L TOR &>/dev/null || iptables -t nat -N TOR

    # Do not redirect Tor itself
    iptables -t nat -C TOR -m owner --uid-owner $TOR_UID -j RETURN 2>/dev/null || \
        iptables -t nat -A TOR -m owner --uid-owner $TOR_UID -j RETURN

    # Do not redirect loopback
    iptables -t nat -C TOR -d 127.0.0.0/8 -j RETURN 2>/dev/null || \
        iptables -t nat -A TOR -d 127.0.0.0/8 -j RETURN

    # Redirect DNS
    #iptables -t nat -C TOR -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
        #iptables -t nat -A TOR -p udp --dport 53 -j REDIRECT --to-ports 5353

    # Redirect all TCP traffic to Tor TransPort
    iptables -t nat -C TOR -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || \
        iptables -t nat -A TOR -p tcp -j REDIRECT --to-ports 9040

    # Apply TOR chain to OUTPUT
    iptables -t nat -C OUTPUT -p tcp -j TOR 2>/dev/null || \
        iptables -t nat -I OUTPUT -p tcp -j TOR

    # Save iptables persistently
    netfilter-persistent save
    netfilter-persistent reload

    echo "Tor enabled ✅"
}

disable_tor() {
    echo "== Stopping Tor =="
    systemctl stop tor

    # Remove TOR chain rules from OUTPUT
    iptables -t nat -D OUTPUT -p tcp -j TOR 2>/dev/null || true

    # Flush and delete TOR chain if exists
    iptables -t nat -F TOR 2>/dev/null || true
    iptables -t nat -X TOR 2>/dev/null || true

    # Save iptables persistently
    netfilter-persistent save
    netfilter-persistent reload

    echo "Tor disabled ✅"
}

status_tor() {
    systemctl status tor --no-pager
    echo
    echo "===== Tor IPTABLES Chain ====="
    iptables -t nat -L TOR -n --line-numbers 2>/dev/null || echo "TOR chain does not exist."
}

# ---------- MENU ----------
clear
echo -e "${red}=========================================${nc}"
echo -e "${blue}             TOR CONTROL                ${nc}"
echo -e "${red}=========================================${nc}"
echo -e ""
echo -e " ${white}1${nc}) Enable Tor (all TCP + DNS through Tor)"
echo -e " ${white}2${nc}) Disable Tor (restore normal connections)"
echo -e " ${white}3${nc}) Enable Tor Autostart After Boot"
echo -e " ${white}4${nc}) Disable Tor Autostart After Boot"
echo -e " ${white}5${nc}) Tor Status"
echo -e ""
echo -e "${red}=========================================${nc}"
echo -e " ${white}0${nc} Back to Menu"
echo -e " Press ${yellow}x${nc} or Ctrl+C to Exit"
echo -e "${red}=========================================${nc}"
echo -e ""
read -p "Select option: " opt
echo -e ""

case $opt in
    1) enable_tor ;;
    2) disable_tor ;;
    3) systemctl enable tor && echo "Tor will start automatically after reboot ✅" ;;
    4) systemctl disable tor && echo "Tor autostart disabled ✅" ;;
    5) status_tor ;;
    0) exit ;;
    *) echo "Invalid choice" ;;
esac
