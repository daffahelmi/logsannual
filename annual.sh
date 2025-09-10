#!/bin/bash

# === Konfigurasi ===
TOKEN="7594414570:AAFriZIyAAFwCw0VwMWPYTFKQ-yN0EyvNFM"
CHAT_ID="7664653146"
VPS_NAME="NAMAVPS"
LOG_FILE="/var/log/vnstat_rx_yearly.log"

# === Daftar paket yang diperlukan ===
DEPENDENCIES=("jq" "bc" "curl" "vnstat")

# Fungsi untuk memeriksa dan menginstal paket yang diperlukan
check_install() {
    local package_name=$1
    if ! command -v $package_name &> /dev/null; then
        echo "$package_name belum terinstal. Menginstal $package_name..."
        apt install -y $package_name
    else
        echo "$package_name sudah terinstal."
    fi
}

# Update apt sekali saja
apt update -y

# Loop untuk cek semua dependensi
for package in "${DEPENDENCIES[@]}"; do
    check_install "$package"
done

# Deteksi interface jaringan
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
echo "Menggunakan interface: $INTERFACE"

# Mengambil data vnstat
RX_DATA=$(vnstat -i "$INTERFACE" -y --json 2>/dev/null)

# Cek data vnstat
if [ -z "$RX_DATA" ]; then
    ERROR_MSG="[$VPS_NAME] Error: Tidak dapat membaca data vnstat untuk $INTERFACE (vnstat mungkin baru saja diinstal)"
    echo "$ERROR_MSG"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$ERROR_MSG"
    exit 1
fi

RX_YEARLY=$(echo "$RX_DATA" | jq -r '.interfaces[0].traffic.year[0].rx? // empty')

# Jika data tahunan tidak ada → estimasi dari bulanan
if [ -z "$RX_YEARLY" ]; then
    RX_MONTHLY=$(echo "$RX_DATA" | jq -r '.interfaces[0].traffic.month[0].rx? // empty')
    if [ -n "$RX_MONTHLY" ]; then
        RX_YEARLY=$((RX_MONTHLY * 12))
        NOTE=" (Estimasi tahunan dari data bulanan)"
    else
        ERROR_MSG="[$VPS_NAME] Error: Data bandwidth tidak tersedia"
        echo "$ERROR_MSG"
        curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
            -d chat_id="$CHAT_ID" \
            -d text="$ERROR_MSG"
        exit 1
    fi
fi

# Konversi ke GB
RX_GB=$(echo "scale=2; $RX_YEARLY / 1024 / 1024 / 1024" | bc)

# Jika lebih dari 1000 GB → tampilkan dalam TB
if (( $(echo "$RX_GB >= 1000" | bc -l) )); then
    RX_TB=$(echo "scale=2; $RX_GB / 1000" | bc)
    DISPLAY_VALUE="$RX_TB TB$NOTE"
else
    DISPLAY_VALUE="$RX_GB GB$NOTE"
fi

# Pesan ke Telegram
MESSAGE="[$VPS_NAME] Penggunaan RX tahun ini ($INTERFACE): $DISPLAY_VALUE"

curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$MESSAGE"

# Simpan log
echo "$(date): [$VPS_NAME] RX ($INTERFACE) Tahun ini: $DISPLAY_VALUE" >> "$LOG_FILE"
