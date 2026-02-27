#!/usr/bin/env bash
set -euo pipefail

echo "=== VPN NODE AUTO DEPLOY START ==="

# --- Root check ---
if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root ❌❌❌"
  exit 1
fi

# --- Non-interactive APT ---
export DEBIAN_FRONTEND=noninteractive

# --- System update ---
apt update -y
apt full-upgrade -y

# --- Packages ---
apt install -y --no-install-recommends \
  curl wget unzip htop ufw net-tools ca-certificates

# --- Enable BBR module persistently ---
mkdir -p /etc/modules-load.d

if ! grep -q "^tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
fi

modprobe tcp_bbr 2>/dev/null || true

# --- sysctl VPN optimization ---
mkdir -p /etc/sysctl.d

cat << 'EOF' > /etc/sysctl.d/99-network-optimizations.conf
# BBR congestion control
# net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Connection optimization
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200

# Queues and buffers
net.core.somaxconn = 2048
net.core.netdev_max_backlog = 2048
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_max_tw_buckets = 10000

# Memory
vm.swappiness = 10
vm.overcommit_memory = 0

# Disable IPv6 (optional)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# No slow-start after idle
net.ipv4.tcp_slow_start_after_idle = 0

# MTU blackhole detection
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1460

# Window scaling
net.ipv4.tcp_window_scaling = 1

# TCP Buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_low_latency = 1

# File limits
fs.file-max = 1048576
EOF

sysctl --system >/dev/null

# --- File limits ---
if ! grep -q "1048576" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi

# --- Applying BBR (external installer) ---
echo
echo " ⚙ Installing BBR3 (external script)..."
echo "--------------------------------------------"

TMP_BBR_SCRIPT="/tmp/install_bbr3.sh"

if wget -q -O "$TMP_BBR_SCRIPT" "https://raw.githubusercontent.com/XDflight/bbr3-debs/refs/heads/build/install_latest.sh"; then
  chmod +x "$TMP_BBR_SCRIPT"
  bash "$TMP_BBR_SCRIPT"

  echo
  echo " 🔍 Final verification:"
  echo "--------------------------------------------"

  cc_value=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  qdisc_value=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
  tfo_value=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "unknown")
  ecn_value=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null || echo "unknown")
  krn_version=$(uname -r 2>/dev/null || echo "unknown")

  rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "unknown")
  wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "unknown")
  tcp_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo "unknown")
  tcp_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo "unknown")
  low_lat=$(sysctl -n net.ipv4.tcp_low_latency 2>/dev/null || echo "unknown")

  echo " ✅ Congestion control: $cc_value"
  echo " ✅ Queue discipline:   $qdisc_value"
  echo " ✅ TCP Fast Open:      $tfo_value"
  echo " ✅ ECN:                $ecn_value"
  echo " ✅ Kernel version:     $krn_version"
  echo
  echo " 📦 Buffers:"
  echo "     rmem_max:    $rmem_max"
  echo "     wmem_max:    $wmem_max"
  echo "     tcp_rmem:    $tcp_rmem"
  echo "     tcp_wmem:    $tcp_wmem"
  echo "     low_latency: $low_lat"
  echo
  echo "============================================"
  echo " ✨ Done."
  echo "============================================"
  echo "============= Reboot recommended ============="
else
  echo "❌ Failed to download BBR3 installer. Check your network or URL."
  exit 1
fi
