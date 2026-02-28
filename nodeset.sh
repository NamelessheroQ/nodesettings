#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SYSCTL_BIN="$(command -v sysctl || echo /sbin/sysctl)"

if [[ ! -x "$SYSCTL_BIN" ]]; then
  echo "sysctl binary not found, check procps installation"
  exit 1
fi


echo "=== VPN NODE AUTO DEPLOY START ==="

# --- Root check ---
if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root ❌❌❌"
  exit 1
fi

# --- System update ---
apt update -y
apt full-upgrade -y

# --- Packages ---
apt install -y --no-install-recommends \
  curl wget unzip htop ufw net-tools ca-certificates procps

# --- Enable BBR module persistently ---
mkdir -p /etc/modules-load.d

if ! grep -q "^tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
fi

modprobe tcp_bbr 2>/dev/null || true

cat << 'EOF' > /etc/sysctl.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 262144
vm.swappiness = 10
net.ipv4.tcp_syncookies = 1
vm.overcommit_memory = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1460
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_keepalive_probes = 5
fs.file-max = 1048576
EOF

"$SYSCTL_BIN" sysctl -p

# --- File limits ---
if ! grep -q "1048576" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi