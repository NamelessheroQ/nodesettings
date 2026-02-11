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

# --- Disable unused services ---
systemctl disable --now snapd || true
systemctl disable --now firewalld || true

# --- UFW firewall ---
ufw default deny incoming
ufw default allow outgoing

ufw allow OpenSSH
ufw allow 443/tcp
ufw allow 2222/tcp

echo "[+] Checking UFW ICMP patch"

if [ -f /etc/ufw/before.rules.bak ]; then
    echo "[!] Backup already exists. Skipping ICMP modification."
else
    echo "[+] Creating backup and applying ICMP hardening"

    cp /etc/ufw/before.rules /etc/ufw/before.rules.bak

    # --- INPUT BLOCK ---
    sed -i '/# ok icmp codes for INPUT/,/# ok icmp code for FORWARD/ {
        s/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP/
        s/-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT/-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP/
        s/-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT/-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP/
        s/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/
    }' /etc/ufw/before.rules

    # --- FORWARD BLOCK ---
    sed -i '/# ok icmp code for FORWARD/,/COMMIT/ {
        s/-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP/
        s/-A ufw-before-forward -p icmp --icmp-type time-exceeded -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP/
        s/-A ufw-before-forward -p icmp --icmp-type parameter-problem -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP/
        s/-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP/
    }' /etc/ufw/before.rules

    # Добавляем source-quench только если его нет
    if ! grep -q "source-quench -j DROP" /etc/ufw/before.rules; then
        sed -i '/-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-forward -p icmp --icmp-type source-quench -j DROP' /etc/ufw/before.rules
    fi

    echo "[+] ICMP hardening applied"
fi

ufw --force enable

echo "[+] Firewall configured safely"

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

# --- Create log directory for Xray / RemnaWave ---
mkdir -p /var/log/remnanode

# Create log files
touch /var/log/remnanode/access.log
touch /var/log/remnanode/error.log

# Set permissions
chown root:root /var/log/remnanode/*.log
chmod 644 /var/log/remnanode/*.log
chown root:root /var/log/remnanode
chmod 755 /var/log/remnanode

echo "[+] Log directory created"

echo "=== DEPLOY FINISHED ==="
echo "➡️ Reboot recommended: reboot"
