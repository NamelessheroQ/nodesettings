#!/bin/bash
set -e

echo "=== VPN NODE AUTO DEPLOY START ==="

# --- root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

# --- Timezone ---
timedatectl set-timezone Europe/Moscow

# --- Update system ---
apt update && apt upgrade -y

# --- Packages ---
apt install -y curl wget unzip htop git ufw net-tools

# --- Disable unused ---
systemctl disable --now snapd || true
systemctl disable --now firewalld || true

# --- UFW firewall ---
ufw default deny incoming
ufw default allow outgoing

ufw allow OpenSSH
ufw allow 443/tcp

ufw --force enable

# --- sysctl VPN optimization ---
cat << 'EOF' > /etc/sysctl.d/99-vpn.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535

net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_syncookies=1

net.ipv4.ip_local_port_range=10000 65000
fs.file-max=1048576
EOF

sysctl --system
modprobe tcp_bbr || true

# --- File limits ---
cat << 'EOF' >> /etc/security/limits.conf
* soft nofile 1048576
* hard nofile 1048576
EOF

# --- Anti-abuse iptables (UFW-safe) ---
iptables -I INPUT -p tcp --syn --dport 443 \
  -m connlimit --connlimit-above 50 -j DROP

iptables -I INPUT -p icmp --icmp-type echo-request \
  -m limit --limit 1/s -j ACCEPT
iptables -I INPUT -p icmp --icmp-type echo-request -j DROP

echo "[+] Creating log directory for Xray / RemnaWave"

sudo mkdir -p /var/log/remnanode

# создаём лог-файлы
sudo touch /var/log/remnanode/access.log
sudo touch /var/log/remnanode/error.log

# права — под root (Xray запускается от root)
sudo chown root:root /var/log/remnanode/*.log
sudo chmod 644 /var/log/remnanode/*.log

# на всякий случай права на директорию
sudo chown root:root /var/log/remnanode
sudo chmod 755 /var/log/remnanode


echo "=== DEPLOY FINISHED ==="
echo "➡️ Reboot recommended: reboot"
