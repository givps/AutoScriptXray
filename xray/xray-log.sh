#!/bin/bash
# =========================================
# Xray Log Viewer Real-Time (Text) - Complete & Colored
# =========================================

ACCESS_LOG="/var/log/xray/access.log"
ERROR_LOG="/var/log/xray/error.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Optional filters (leave empty to show all)
FILTER_PROTO=""   # Example: "vless" or "trojan"
FILTER_IP=""      # Example: "162.159.193.8"

# Header
echo -e "TYPE\tTime\t\t\tProtocol\tDestination IP\tMessage"
echo "---------------------------------------------------------------"

# Format access log
format_access() {
    local line="$1"
    # Extract time column (YYYY/MM/DD HH:MM:SS)
    time=$(echo "$line" | awk '{print $1" "$2}')
    
    # Extract protocol from message
    proto=$(echo "$line" | grep -oP 'proxy/\K[^:]+' | head -1)
    
    # Extract destination IP and port
    ipport=$(echo "$line" | grep -oP 'to udp:\K[0-9.]+:[0-9]+' | head -1)
    
    # Remaining message
    msg=$(echo "$line" | sed -E 's/^[0-9\/: ]+\s\[.*\]\s\[.*\]\sproxy\/[^:]+:\s//')

    # Protocol filter
    if [[ -n "$FILTER_PROTO" && "$proto" != "$FILTER_PROTO" ]]; then
        return
    fi

    # IP filter
    if [[ -n "$FILTER_IP" && "$ipport" != *"$FILTER_IP"* ]]; then
        return
    fi

    # Determine color
    if echo "$line" | grep -q "\[Info\]"; then
        COLOR="$GREEN"
    elif echo "$line" | grep -q "\[Warning\]"; then
        COLOR="$ORANGE"
    else
        COLOR="$RED"
    fi

    echo -e "${COLOR}ACCESS\t$time\t$proto\t$ipport\t$msg${NC}"
}

# Format error log
format_error() {
    local line="$1"
    echo -e "${RED}ERROR\t$line${NC}"
}

# Real-time monitoring of both logs without file headers
tail -n 50 -q -f "$ACCESS_LOG" "$ERROR_LOG" | while read -r line; do
    if [[ "$line" == *"error"* || "$line" == *"ERROR"* ]]; then
        format_error "$line"
    else
        format_access "$line"
    fi
done
