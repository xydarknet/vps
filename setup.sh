#!/bin/bash
# setup.sh by xydark – Full Auto XRAY + Bot + Domain

set -e

# ========================================
# 1. Disable IPv6
# ========================================
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
sysctl -p

# ========================================
# 2. Whitelist IP
# ========================================
MYIP=$(curl -s ifconfig.me)
WL="https://raw.githubusercontent.com/xydarknet/x/main/whitelist.txt"
if ! curl -fsSL "$WL" | grep -wq "$MYIP"; then
  echo "⛔ IP $MYIP belum diapprove. Hubungi admin."
  exit 1
else
  echo "✅ IP $MYIP di whitelist."
fi

# ========================================
# 3. Install Paket Wajib
# ========================================
echo "▶ Install paket penting..."
apt update -y > /dev/null 2>&1
apt install -y curl grep dnsutils python3-pip > /dev/null 2>&1

# ========================================
# 4. Install Xray Core
# ========================================
echo "▶ Installing Xray..."
mkdir -p /tmp/xray
curl -Ls -o /tmp/xray/install.sh https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh
bash /tmp/xray/install.sh install

# Buat service manual jika belum ada
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=XRAY Core Service - by xydark
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNPROC=10000
LimitNOFILE=1000000
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl start xray

# ========================================
# 5. Setup Domain
# ========================================
echo -e "▶ Menyiapkan konfigurasi domain & bot..."
mkdir -p /etc/xray /etc/xydark
touch /etc/xydark/approved-ip.json

# DETEKSI DOMAIN OTOMATIS / MANUAL
if [[ ! -f /etc/xray/domain ]]; then
    echo -e "\e[96m🔍 Mendeteksi domain otomatis...\e[0m"
    myip=$(curl -s ipv4.icanhazip.com)
    resolved_domain=$(dig +short -x "$myip" | sed 's/\.$//' | grep -Eo '([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}')
    
    if [[ -n "$resolved_domain" ]]; then
        domain="$resolved_domain"
        echo -e "✅ Domain otomatis terdeteksi: \e[32m$domain\e[0m"
    else
        echo -e "\e[93m⚠️  Tidak bisa mendeteksi domain secara otomatis.\e[0m"
        read -rp $'\e[36m🔧 Masukkan domain manual (contoh: vpn.xydark.biz.id): \e[0m' domain
    fi

    echo "$domain" > /etc/xray/domain
else
    domain=$(cat /etc/xray/domain)
    echo -e "✔ Domain ditemukan: \e[32m$domain\e[0m"
fi

# ========================================
# 6. Token & ID Bot Telegram
# ========================================
if [[ ! -s /etc/xydark/bot-token ]]; then
  read -rp "Masukkan Bot Token Telegram: " TKN
  echo "$TKN" > /etc/xydark/bot-token
fi
if [[ ! -s /etc/xydark/owner-id ]]; then
  read -rp "Masukkan Chat ID Telegram: " CID
  echo "$CID" > /etc/xydark/owner-id
fi

# Simpan config bot
cat > /etc/xydark/config.json <<EOF
{"token":"$(cat /etc/xydark/bot-token)","owner_id":$(cat /etc/xydark/owner-id)}
EOF

# ========================================
# 7. Download Script XRAY
# ========================================
echo "▶ Mengunduh semua script XRAY..."
BASE_URL="https://raw.githubusercontent.com/xydarknet/a/main"

declare -a files=(
  addvmess
  addvless
  addtrojan
  addvmessgrpc
  addvlessgrpc
  addtrojangrpc
)

for f in "${files[@]}"; do
  wget -qO /usr/bin/$f "$BASE_URL/Xray/$f"
  chmod +x /usr/bin/$f
done

chmod +x /usr/bin/add*

# ========================================
# 8. Menu CLI
# ========================================
echo "▶ Mengunduh script menu..."
for m in menu menu-ssh menu-xray menu-set menu-createxray; do
  wget -qO /usr/bin/$m https://raw.githubusercontent.com/xydarknet/x/main/menu/$m.sh
  chmod +x /usr/bin/$m
done

grep -qxF "menu" /root/.bashrc || echo "menu" >> /root/.bashrc

# ========================================
# 9. System Info & Check IP saat login
# ========================================
wget -qO /etc/xydark/system-info.sh https://raw.githubusercontent.com/xydarknet/x/main/system-info.sh
chmod +x /etc/xydark/system-info.sh
grep -qxF "bash /etc/xydark/system-info.sh" /root/.bashrc || echo "bash /etc/xydark/system-info.sh" >> /root/.bashrc

# ========================================
# 10. Sistem Approval IP Telegram
# ========================================
cat > /etc/xydark/request-ip.sh <<'EOF'
#!/bin/bash
token=$(cat /etc/xydark/bot-token)
cid=$(cat /etc/xydark/owner-id)
ip=$(curl -s ifconfig.me)
host=$(hostname)
msg="🛑 New VPS IP request!\nHostname: \`$host\`\nIP: \`$ip\`"
kb='{"inline_keyboard":[[{"text":"✅ Approve","callback_data":"approve_30d_'$ip'"},{"text":"❌ Reject","callback_data":"reject_'$ip'"}]]}'
curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" -d chat_id="$cid" -d text="$msg" -d parse_mode="Markdown" -d reply_markup="$kb"
EOF
chmod +x /etc/xydark/request-ip.sh

cat > /etc/xydark/check-ip.sh <<'EOF'
#!/bin/bash
ip=$(curl -s ifconfig.me)
f=/etc/xydark/approved-ip.json
[[ ! -f "$f" ]] && echo "[]" > "$f"
if ! grep -q "$ip" "$f"; then
  bash /etc/xydark/request-ip.sh
  exit 1
fi
EOF
chmod +x /etc/xydark/check-ip.sh
grep -qxF "bash /etc/xydark/check-ip.sh || exit" /root/.bashrc || echo "bash /etc/xydark/check-ip.sh || exit" >> /root/.bashrc

# ========================================
# 11. Install Bot Telegram
# ========================================
echo "▶ Install Telegram Bot service..."
pip3 install python-telegram-bot==20.3 httpx

mkdir -p /etc/xydark/bot
for f in bot.py bot.conf owner.conf allowed.conf; do
  wget -qO /etc/xydark/bot/$f https://raw.githubusercontent.com/xydarknet/x/main/bot/$f
done

cat > /etc/systemd/system/xydark-bot.service <<EOF
[Unit]
Description=XYDARK Telegram Bot
After=network.target
[Service]
ExecStart=/usr/bin/python3 /etc/xydark/bot/bot.py
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable xydark-bot
systemctl start xydark-bot

# ========================================
# 12. Update Script Tool
# ========================================
cat > /etc/xydark/tools/update-script <<'EOF'
#!/bin/bash
echo "▶ Mengunduh update terbaru..."
cd /usr/bin
wget -q https://raw.githubusercontent.com/xydarknet/x/main/menu/menu.sh -O menu
wget -q https://raw.githubusercontent.com/xydarknet/x/main/menu/menu-xray.sh -O menu-xray
wget -q https://raw.githubusercontent.com/xydarknet/x/main/menu/menu-ssh.sh -O menu-ssh
wget -q https://raw.githubusercontent.com/xydarknet/x/main/menu/menu-set.sh -O menu-set
chmod +x menu*
echo "✅ Semua script telah diperbarui."
EOF
chmod +x /etc/xydark/tools/update-script
ln -sf /etc/xydark/tools/update-script /usr/bin/update-script

# ✅ DONE
clear
echo -e "\n✅ SETUP SELESAI! Ketik: \e[1;36mmenu\e[0m\n"
