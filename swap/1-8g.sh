#!/bin/bash
# =========================================
# Smart Auto Swapfile Maker
# Dynamically creates swap based on RAM size (1GB–8GB)
# Debian/Ubuntu
# =========================================

SWAPFILE="/swapfile"

echo "=== Smart Auto Swapfile Maker ==="

# Must be run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root!"
  exit 1
fi

# Get total RAM in MiB
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_GB=$(( (TOTAL_RAM + 512) / 1024 ))  # round to nearest GB

echo "➡️ Detected RAM: ${TOTAL_GB} GB"

# Determine swap size based on RAM
case $TOTAL_GB in
  1)  SWAPSIZE="2G" ;;   # 2x for 1GB RAM
  2)  SWAPSIZE="2G" ;;   # 1x for 2GB
  3)  SWAPSIZE="2G" ;;   # slightly below 1x
  4)  SWAPSIZE="2G" ;;   # fixed 2GB
  5)  SWAPSIZE="1G" ;;
  6)  SWAPSIZE="1G" ;;
  7)  SWAPSIZE="1G" ;;
  8)  SWAPSIZE="1G" ;;
  *)  SWAPSIZE="1G" ;;   # default for >8GB
esac

echo "➡️ Creating swapfile of size: ${SWAPSIZE}"

# Check if swap is already active
if swapon --show | grep -q "$SWAPFILE"; then
  echo "✅ Swapfile already active: $SWAPFILE"
  exit 0
fi

# Create swapfile
fallocate -l $SWAPSIZE $SWAPFILE 2>/dev/null || dd if=/dev/zero of=$SWAPFILE bs=1M count=$((${SWAPSIZE%G} * 1024))
chmod 600 $SWAPFILE
mkswap $SWAPFILE
swapon $SWAPFILE

# Add to /etc/fstab for persistence
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# Kernel optimizations
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=50
grep -qxF 'vm.swappiness=10' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
grep -qxF 'vm.vfs_cache_pressure=50' /etc/sysctl.conf || echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf

echo "=== Swapfile created and activated successfully ==="
swapon --show
free -h
