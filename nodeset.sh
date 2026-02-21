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
# --- # BBRv3 + FQ (ускорение TCP) ---
# net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- Оптимизация соединений (чтобы порты не заканчивались) ---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200

# --- Очереди и буферы (баланс между скоростью и потреблением RAM) ---
net.core.somaxconn = 2048
net.core.netdev_max_backlog = 2048
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_max_tw_buckets = 10000

# --- Память (чтобы сервер не зависал при нехватке RAM) ---
vm.swappiness = 10
vm.overcommit_memory = 0

# --- Отключение IPv6 (если не используешь, лучше выключить) ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# --- Запрет на "засыпание" скорости ---
net.ipv4.tcp_slow_start_after_idle = 0

# --- Борьба с "черными дырами" MTU ---
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024

# --- Принудительное включение масштабирования окон (обычно включено, но лучше зафиксировать) ---
net.ipv4.tcp_window_scaling = 1

# --- TCP Buffers (16-32 MB) | (разгон скорости) ---
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_low_latency = 1

# File limits
fs.file-max = 1048576
EOF

# --- Удаляем старые конфиги, чтобы не мешали нашим настройкам ---
if [ -f /etc/sysctl.d/99-network-optimizations.conf ]; then
    rm -f /etc/sysctl.d/99-network-optimizations.conf
    echo "[+] Removed /etc/sysctl.d/99-network-optimizations.conf"
fi

if [ -f /etc/sysctl.d/99-sysctl.conf ]; then
    rm -f /etc/sysctl.d/99-sysctl.conf
    echo "[+] Removed /etc/sysctl.d/99-sysctl.conf"
fi

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

# --- Applying BBR (external installer) --- #
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

  rmem_max=$(sysctl -n net.core.rmem_max)
  wmem_max=$(sysctl -n net.core.wmem_max)
  tcp_rmem=$(sysctl -n net.ipv4.tcp_rmem)
  tcp_wmem=$(sysctl -n net.ipv4.tcp_wmem)
  low_lat=$(sysctl -n net.ipv4.tcp_low_latency)

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
else
  echo "❌ Failed to download BBR3 installer. Check your network or URL."
  exit 1
fi