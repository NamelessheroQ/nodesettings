#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/sbin:/sbin:$PATH"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root ❌❌❌"
  exit 1
fi

apt update -y
apt full-upgrade -y

apt install -y --no-install-recommends \
  curl sudo wget unzip htop ufw net-tools ca-certificates procps

mkdir -p /etc/modules-load.d

if ! grep -q "^tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
fi

modprobe tcp_bbr 2>/dev/null || true

mkdir -p /etc/sysctl.d

cat << 'EOF' > /etc/sysctl.d/99-network-optimizations.conf
# ============================================================
#  Network & Kernel tuning
# ============================================================

# --- Congestion control (BBR) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TCP tuning ---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 262144

# --- Buffers / queues ---
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 5000
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
fs.file-max = 2097152

# --- Memory ---
vm.swappiness = 10
vm.overcommit_memory = 0

# ============================================================
#  IPv4 Hardening
# ============================================================
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 1
net.ipv4.conf.default.secure_redirects = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.icmp_ratemask = 88089
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.ip_forward = 0

# ============================================================
#  IPv6 — fully disabled
# ============================================================
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.forwarding = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# ============================================================
#  Kernel hardening
# ============================================================
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

sysctl --system >/dev/null

if ! grep -q "1048576" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi

echo "⚙ Installing BBR3"

TMP_BBR_SCRIPT="/tmp/install_bbr3.sh"

if wget -q -O "$TMP_BBR_SCRIPT" "https://raw.githubusercontent.com/XDflight/bbr3-debs/refs/heads/build/install_latest.sh"; then
  chmod +x "$TMP_BBR_SCRIPT"
  bash "$TMP_BBR_SCRIPT"
  cc_value=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  qdisc_value=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
  tfo_value=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo "unknown")
  ecn_value=$(sysctl -n net.ipv4.tcp_ecn 2>/dev/null || echo "unknown")
  krn_version=$(uname -r 2>/dev/null || echo "unknown")
  rmem_max=$(sysctl -n net.core.rmem_max)
  wmem_max=$(sysctl -n net.core.wmem_max)
  tcp_rmem=$(sysctl -n net.ipv4.tcp_rmem)
  tcp_wmem=$(sysctl -n net.ipv4.tcp_wmem)
  low_lat=$(sysctl -n net.ipv4.tcp_low_latency)
else
  echo "❌ Failed to download BBR3 installer. Check your network or URL."
  exit 1
fi
