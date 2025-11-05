#!/bin/bash
# =========================================
# Auto Swapfile Maker - 1GB
# Tested on Ubuntu/Debian
# =========================================

SWAPFILE="/swapfile"
SWAPSIZE="1G"

echo "=== Creating swapfile of size $SWAPSIZE ==="

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root!"
  exit 1
fi

# Check if swap already exists
if swapon --show | grep -q "$SWAPFILE"; then
  echo "✅ Swapfile already active: $SWAPFILE"
  exit 0
fi

# Create swapfile
echo "➡️ Creating swap file..."
fallocate -l $SWAPSIZE $SWAPFILE 2>/dev/null || dd if=/dev/zero of=$SWAPFILE bs=1M count=1024

# Set proper permissions
chmod 600 $SWAPFILE

# Format as swap
mkswap $SWAPFILE

# Enable swap
swapon $SWAPFILE

# Add to /etc/fstab for persistence
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# Kernel optimization
sysctl -w vm.swappiness=10
sysctl -w vm.vfs_cache_pressure=50

# Save settings permanently
grep -qxF 'vm.swappiness=10' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
grep -qxF 'vm.vfs_cache_pressure=50' /etc/sysctl.conf || echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf

echo "=== Swapfile has been successfully created and activated ==="
swapon --show
free -h
