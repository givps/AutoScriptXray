#!/bin/bash
# =========================================
# Clear RAM Cache (Simple Version)
# =========================================

# Colors
red='\e[1;31m'
green='\e[0;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
nc='\e[0m'

# ==========================================

clear

echo -e "${blue}=========================================${nc}"
echo -e "${blue}          CLEAR RAM CACHE           ${nc}"
echo -e "${blue}=========================================${nc}"
echo ""

# Show current memory
echo -e "${yellow}Current Memory Usage:${nc}"
free -h
echo ""

# Clear cache
echo -e "[ ${green}INFO${nc} ] Clearing RAM cache..."
sync
echo 1 > /proc/sys/vm/drop_caches
echo 2 > /proc/sys/vm/drop_caches 2>/dev/null
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
sleep 2

echo -e "[ ${green}SUCCESS${nc} ] RAM cache cleared!"
echo ""

# Show memory after cleanup
echo -e "${green}Memory After Cleanup:${nc}"
free -h

echo ""
echo -e "${blue}=========================================${nc}"
echo -e "${yellow}Returning to menu in 2 seconds...${nc}"
sleep 2
menu

