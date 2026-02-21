#!/usr/bin/env bash
set -euo pipefail

echo "=== VPN NODE AUTO DEPLOY START ==="

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

# --- System update ---
apt update -y
apt upgrade -y

# --- Packages ---
apt install -y curl wget unzip htop ufw net-tools

# --- Disable unused services ---
systemctl disable --now snapd 2>/dev/null || true
systemctl disable --now firewalld 2>/dev/null || true

# --- UFW firewall ---
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 443/tcp
ufw allow 2222/tcp
ufw --force enable

echo "[+] Base firewall configured"

# --- ICMP hardening (как делал вручную) ---
echo "[+] Checking UFW ICMP patch"

if [ ! -f /etc/ufw/before.rules.bak ]; then
    echo "[+] Creating backup of UFW rules"
    cp /etc/ufw/before.rules /etc/ufw/before.rules.bak
fi

# INPUT block
sed -i '/# ok icmp codes for INPUT/,/# ok icmp code for FORWARD/ {
    s/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP/
    s/-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT/-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP/
    s/-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT/-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP/
    s/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/
}' /etc/ufw/before.rules

# FORWARD block
sed -i '/# ok icmp code for FORWARD/,/COMMIT/ {
    s/-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP/
    s/-A ufw-before-forward -p icmp --icmp-type time-exceeded -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP/
    s/-A ufw-before-forward -p icmp --icmp-type parameter-problem -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP/
    s/-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP/
}' /etc/ufw/before.rules

sed -i '/-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-forward -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules

ufw --force reload

echo "[+] ICMP hardening applied"

# Load BBR module
if ! grep -q "^tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
  echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

modprobe tcp_bbr 2>/dev/null || true

# --- sysctl VPN optimization ---
cat << 'EOF' > /etc/sysctl.d/99-vpn.conf
# Disable IPv6 (если не используешь)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Queue tuning
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# TCP optimization
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1

# UNIVERSAL KEEPALIVE (ПК + мобильные)
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# Ports
net.ipv4.ip_local_port_range = 10000 65000

# File limits
fs.file-max = 1048576
EOF

sysctl --system > /dev/null

# --- File limits ---
if ! grep -q "1048576" /etc/security/limits.conf; then
  cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
EOF
fi

# --- Log directory ---
LOG_DIR="/var/log/remnanode"

mkdir -p "$LOG_DIR"
touch "$LOG_DIR/access.log" "$LOG_DIR/error.log"

chown root:root "$LOG_DIR" "$LOG_DIR"/*.log
chmod 755 "$LOG_DIR"
chmod 644 "$LOG_DIR"/*.log

echo "[+] Log directory created"

echo "=== DEPLOY FINISHED ==="
echo "➡️ Reboot recommended"
