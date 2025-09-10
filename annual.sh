#!/bin/bash

# ======================
# Lokasi script utama
# ======================
TARGET_SCRIPT="/usr/local/bin/annual.sh"
CRON_FILE="/etc/cron.d/annual_job"

# ======================
# Isi script monitoring
# ======================
cat > $TARGET_SCRIPT <<'EOF'
#!/bin/bash

TOKEN="7594414570:AAFriZIyAAFwCw0VwMWPYTFKQ-yN0EyvNFM"
CHAT_ID="7664653146"
LOG_FILE="/var/log/vnstat_rx_yearly.log"
VPS_NAME_FILE="/var/log/vps_name.conf"

# Cek dan load VPS_NAME
if [ -f "$VPS_NAME_FILE" ]; then
    VPS_NAME=$(cat "$VPS_NAME_FILE")
    echo "Nama VPS saat ini: $VPS_NAME"
    read -p "Apakah ingin mengubah nama VPS? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        read -p "Masukkan nama VPS baru: " VPS_NAME
        echo "$VPS_NAME" > "$VPS_NAME_FILE"
    fi
else
    read -p "Masukkan nama VPS: " VPS_NAME
    echo "$VPS_NAME" > "$VPS_NAME_FILE"
fi

DEPENDENCIES=("jq" "bc" "curl" "vnstat")
check_install() {
    local package_name=$1
    if ! command -v $package_name &> /dev/null; then
        echo "$package_name belum terinstal. Menginstal $package_name..."
        apt update
        apt install -y $package_name
    fi
}
for package in "${DEPENDENCIES[@]}"; do
    check_install "$package"
done

detect_interface() {
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
    for intf in "${interfaces[@]}"; do
        if [[ "$intf" == "eth0" || "$intf" == "ens3" ]]; then
            echo "$intf"
            return
        fi
    done
    [ -n "${interfaces[0]}" ] && echo "${interfaces[0]}" || echo "eth0"
}

INTERFACE=$(detect_interface)
RX_DATA=$(vnstat -i "$INTERFACE" -y --json 2>/dev/null)

if [ -z "$RX_DATA" ]; then
    ERROR_MSG="[$VPS_NAME] Error: Tidak dapat membaca data vnstat untuk $INTERFACE"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="$ERROR_MSG"
    exit 1
fi

RX_YEARLY=$(echo "$RX_DATA" | jq -r '.interfaces[0].traffic.year[0].rx? // empty')
if [ -z "$RX_YEARLY" ]; then
    RX_MONTHLY=$(echo "$RX_DATA" | jq -r '.interfaces[0].traffic.month[0].rx? // empty')
    if [ -n "$RX_MONTHLY" ]; then
        RX_YEARLY=$((RX_MONTHLY * 12))
        NOTE=" (Estimasi tahunan dari data bulanan)"
    else
        ERROR_MSG="[$VPS_NAME] Error: Data bandwidth tidak tersedia"
        curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" -d text="$ERROR_MSG"
        exit 1
    fi
fi

RX_GB=$(echo "scale=2; $RX_YEARLY / 1024 / 1024 / 1024" | bc)
if (( $(echo "$RX_GB >= 1000" | bc -l) )); then
    RX_TB=$(echo "scale=2; $RX_GB / 1000" | bc)
    DISPLAY_VALUE="$RX_TB TB$NOTE"
else
    DISPLAY_VALUE="$RX_GB GB$NOTE"
fi

MESSAGE="[$VPS_NAME] Penggunaan RX: $DISPLAY_VALUE"
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" -d text="$MESSAGE"

echo "$(date): [$VPS_NAME] RX ($INTERFACE) Tahun ini: $DISPLAY_VALUE" >> "$LOG_FILE"
EOF

# ======================
# Set permission
# ======================
chmod +x $TARGET_SCRIPT

# ======================
# Tambahkan cron job
# ======================
echo "0 */1 * * * root $TARGET_SCRIPT" | tee $CRON_FILE
chmod 644 $CRON_FILE
systemctl restart cron

# ======================
# Jalankan sekali untuk tes
# ======================
echo "🚀 Menjalankan script pertama kali untuk test..."
$TARGET_SCRIPT

echo "✅ Script berhasil dibuat di $TARGET_SCRIPT, cron job ditambahkan, dan notifikasi test dikirim."
