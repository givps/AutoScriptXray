#!/bin/bash
# =====================================
# TOR CONTROL SCRIPT (Enable / Disable)
# =====================================

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
    iptables -t nat -C TOR -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null || \
        iptables -t nat -A TOR -p udp --dport 53 -j REDIRECT --to-ports 5353

    # Redirect TCP traffic to Tor TransPort
    iptables -t nat -C TOR -p tcp -j REDIRECT --to-ports 9040 2>/dev/null || \
        iptables -t nat -A TOR -p tcp -j REDIRECT --to-ports 9040

    # Apply TOR chain to OUTPUT
    iptables -t nat -C OUTPUT -p tcp -j TOR 2>/dev/null || \
        iptables -t nat -I OUTPUT -p tcp -j TOR

    # Save rules
    netfilter-persistent save
    netfilter-persistent reload

    echo "Tor enabled ✅"
}

disable_tor() {
    echo "== Stopping Tor =="
    systemctl stop tor

    # Remove TOR chain rules from OUTPUT
    iptables -t nat -D OUTPUT -p tcp -j TOR 2>/dev/null || true

    # Flush TOR chain if exists
    iptables -t nat -F TOR 2>/dev/null || true
    iptables -t nat -X TOR 2>/dev/null || true

    # Save rules
    netfilter-persistent save
    netfilter-persistent reload

    echo "Tor disabled ✅"
}

status_tor() {
    systemctl status tor --no-pager
}

# ---------- MENU ----------
clear
echo "========== TOR CONTROL =========="
echo "1) Enable Tor (all TCP + DNS through Tor)"
echo "2) Disable Tor (restore normal connections)"
echo "3) Tor Status"
echo "0) Exit"
echo "================================"
read -p "Select option: " opt
case $opt in
    1) enable_tor ;;
    2) disable_tor ;;
    3) status_tor ;;
    0) exit ;;
    *) echo "Invalid choice" ;;
esac
