#!/bin/bash

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Struktur Folder Baru: ~/lokal
WORKDIR="$HOME/lokal"
BIN_DIR="$WORKDIR/bin"
CONF_DIR="$WORKDIR/conf"
LOG_DIR="$WORKDIR/logs"

# File Paths
USER_DATA="$CONF_DIR/user_data.conf"
XRAY_CONFIG="$CONF_DIR/config.json"
XRAY_BIN="$BIN_DIR/xray"
CF_BIN="$BIN_DIR/cloudflared"

# Log Files
LOG_XRAY="$LOG_DIR/xray.log"
LOG_CF="$LOG_DIR/cloudflared.log"

# URL Repo untuk Update
REPO_URL="https://raw.githubusercontent.com/2026musik-code/lokal/main/install.sh"

# Fungsi Header
header() {
    clear
    echo -e "${CYAN}"
    echo "  _    _ _    ___ ____ ____   _____                       _ "
    echo " | |  | | |  | __/ ___/ ___| |_   _|   _ _ __  _ __   ___| |"
    echo " | |  | | |  | _|\___ \___ \   | || | | | '_ \| '_ \ / _ \ |"
    echo " | |__| | |__| |___) |___) |  | || |_| | | | | | | |  __/ |"
    echo "  \____/|____|___|____/____/   |_| \__,_|_| |_|_| |_|\___|_|"
    echo -e "${NC}"
    echo -e "${YELLOW}       Xray-Core + Cloudflare Tunnel Installer for Termux${NC}"
    echo -e "${CYAN}==============================================================${NC}"
}

# Cek Dependencies
check_dependencies() {
    if [ -z "$DEPS_CHECKED" ]; then
        echo -e "${YELLOW}[*] Mengecek dependencies...${NC}"
        packages=("curl" "wget" "zip" "jq" "openssl" "util-linux")
        for pkg in "${packages[@]}"; do
            if ! command -v "$pkg" &> /dev/null; then
                echo -e "${RED}[!] $pkg belum terinstall. Menginstall...${NC}"
                pkg install "$pkg" -y
            fi
        done
        export DEPS_CHECKED=1
    fi
}

# Setup Folder Structure
setup_folders() {
    mkdir -p "$WORKDIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$CONF_DIR"
    mkdir -p "$LOG_DIR"
}

# Install Binaries
install_binaries() {
    setup_folders

    # Cek Xray: Hanya download jika file tidak ada atau tidak executable
    if [ -f "$XRAY_BIN" ] && [ -x "$XRAY_BIN" ]; then
        echo -e "${GREEN}[+] Xray sudah terinstall. Melewati unduhan.${NC}"
    else
        echo -e "${YELLOW}[*] Mencari versi terbaru Xray-Core...${NC}"
        LATEST_XRAY_TAG=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)

        if [ -z "$LATEST_XRAY_TAG" ] || [ "$LATEST_XRAY_TAG" == "null" ]; then
             echo -e "${RED}[!] Gagal mendapatkan versi Xray. Cek koneksi internet.${NC}"
             exit 1
        fi

        echo -e "${GREEN}[+] Versi terbaru: $LATEST_XRAY_TAG${NC}"
        echo -e "${YELLOW}[*] Mendownload Xray-Core ($LATEST_XRAY_TAG)...${NC}"
        wget -q --show-progress "https://github.com/XTLS/Xray-core/releases/download/$LATEST_XRAY_TAG/Xray-linux-arm64-v8a.zip" -O "$BIN_DIR/xray.zip"

        echo -e "${YELLOW}[*] Mengekstrak Xray...${NC}"
        unzip -o "$BIN_DIR/xray.zip" -d "$BIN_DIR" > /dev/null
        rm "$BIN_DIR/xray.zip"
        chmod +x "$XRAY_BIN"
        echo -e "${GREEN}[+] Xray berhasil diinstall.${NC}"
    fi

    # Cek Cloudflared
    if [ -f "$CF_BIN" ] && [ -x "$CF_BIN" ]; then
        echo -e "${GREEN}[+] Cloudflared sudah terinstall. Melewati unduhan.${NC}"
    else
        echo -e "${YELLOW}[*] Mendownload Cloudflared...${NC}"
        wget -q --show-progress "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" -O "$CF_BIN"
        chmod +x "$CF_BIN"
        echo -e "${GREEN}[+] Cloudflared berhasil diinstall.${NC}"
    fi
}

# Setup Wizard
setup_wizard() {
    if [ ! -f "$USER_DATA" ]; then
        header
        echo -e "${YELLOW}[SETUP WIZARD]${NC}"
        echo -e "File konfigurasi belum ditemukan. Silakan isi data berikut:"
        echo ""

        while [ -z "$CF_TOKEN" ]; do
            read -p "Masukkan Cloudflare Tunnel Token: " CF_TOKEN
        done

        while [ -z "$USER_DOMAIN" ]; do
            read -p "Masukkan Domain Full (contoh: sub.domain.com): " USER_DOMAIN
        done

        # Generate UUID
        if command -v uuidgen &> /dev/null; then
            UUID=$(uuidgen)
        else
            UUID=$(cat /proc/sys/kernel/random/uuid)
        fi
        echo -e "${GREEN}[+] UUID Generated: $UUID${NC}"

        # Simpan data
        echo "TOKEN=\"$CF_TOKEN\"" > "$USER_DATA"
        echo "DOMAIN=\"$USER_DOMAIN\"" >> "$USER_DATA"
        echo "UUID=\"$UUID\"" >> "$USER_DATA"

        # Buat Config Xray
        cat <<EOF > "$XRAY_CONFIG"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
        echo -e "${GREEN}[+] Konfigurasi disimpan!${NC}"
        sleep 2
    fi
}

# Start Tunnel
start_tunnel() {
    source "$USER_DATA"

    # Cek apakah sudah jalan
    if pgrep -f "$XRAY_BIN" > /dev/null; then
        echo -e "${RED}[!] Xray sudah berjalan.${NC}"
    else
        echo -e "${YELLOW}[*] Menjalankan Xray...${NC}"
        # Jalankan dari folder bin untuk memastikan path ./xray benar jika ada dependensi lokal,
        # tapi config ada di folder conf. Gunakan path absolut untuk amannya.

        # Redirect output ke file log
        # Pastikan menggunakan path absolut ke binary dan config
        nohup "$XRAY_BIN" run -c "$XRAY_CONFIG" > "$LOG_XRAY" 2>&1 &
    fi

    if pgrep -f "$CF_BIN" > /dev/null; then
         echo -e "${RED}[!] Cloudflared sudah berjalan.${NC}"
    else
        echo -e "${YELLOW}[*] Menjalankan Cloudflared...${NC}"
        # Redirect output ke file log
        nohup "$CF_BIN" tunnel run --token "$TOKEN" > "$LOG_CF" 2>&1 &
    fi

    sleep 2
    echo -e "${GREEN}[+] Tunnel berhasil dijalankan!${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Stop Tunnel
stop_tunnel() {
    echo -e "${YELLOW}[*] Menghentikan proses...${NC}"
    pkill -f "$XRAY_BIN"
    pkill -f "$CF_BIN"
    echo -e "${GREEN}[+] Semua proses dimatikan.${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Ambil Link
get_link() {
    source "$USER_DATA"
    LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=%2Fvless#Termux-VLESS"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}VLESS LINK:${NC}"
    echo -e "${LINK}"
    echo -e "${CYAN}==============================================================${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Re-install
reinstall() {
    echo -e "${RED}[!] PERINGATAN: Ini akan menghapus semua file (binaries, config, log)!${NC}"
    read -p "Apakah Anda yakin? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        stop_tunnel
        rm -rf "$WORKDIR"
        echo -e "${GREEN}[+] Folder $WORKDIR dihapus. Script akan restart...${NC}"
        sleep 1
        exec "$0"
    fi
}

# Cek Logs
view_logs() {
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}LOG XRAY (Terakhir 20 Baris):${NC}"
    if [ -f "$LOG_XRAY" ]; then
        tail -n 20 "$LOG_XRAY"
    else
        echo -e "${RED}File Log Xray tidak ditemukan.${NC}"
    fi
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    echo -e "${YELLOW}LOG CLOUDFLARED (Terakhir 20 Baris):${NC}"
    if [ -f "$LOG_CF" ]; then
        tail -n 20 "$LOG_CF"
    else
        echo -e "${RED}File Log Cloudflared tidak ditemukan.${NC}"
    fi
    echo -e "${CYAN}==============================================================${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Update Script
update_script() {
    echo -e "${YELLOW}[*] Mengupdate script dari repository...${NC}"
    echo -e "${CYAN}Repo: $REPO_URL${NC}"

    if wget -q --show-progress "$REPO_URL" -O "$0.tmp"; then
        mv "$0.tmp" "$0"
        chmod +x "$0"
        echo -e "${GREEN}[+] Update berhasil! Me-restart script...${NC}"
        sleep 1
        exec "$0"
    else
        echo -e "${RED}[!] Gagal download update. Periksa koneksi atau URL repository.${NC}"
        rm -f "$0.tmp"
        read -p "Tekan Enter untuk kembali ke menu..."
    fi
}

# Main Logic
check_dependencies
install_binaries
setup_wizard

while true; do
    source "$USER_DATA"

    # Cek Status
    if pgrep -f "$XRAY_BIN" > /dev/null; then
        XRAY_STATUS="${GREEN}ON${NC}"
    else
        XRAY_STATUS="${RED}OFF${NC}"
    fi

    if pgrep -f "$CF_BIN" > /dev/null; then
        CF_STATUS="${GREEN}ON${NC}"
    else
        CF_STATUS="${RED}OFF${NC}"
    fi

    header
    echo -e "Domain: ${YELLOW}$DOMAIN${NC}"
    echo -e "Status Xray: $XRAY_STATUS | Status Tunnel: $CF_STATUS"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "[1] Start Tunnel"
    echo -e "[2] Stop Tunnel"
    echo -e "[3] Ambil Link Akun"
    echo -e "[4] Update/Re-install (Hapus Data)"
    echo -e "[5] Cek Log Error"
    echo -e "[6] Update Script (Dari Repo)"
    echo -e "[0] Keluar"
    echo -e "${CYAN}==============================================================${NC}"
    read -p "Pilih menu: " choice

    case $choice in
        1) start_tunnel ;;
        2) stop_tunnel ;;
        3) get_link ;;
        4) reinstall ;;
        5) view_logs ;;
        6) update_script ;;
        0) echo -e "${GREEN}Terima kasih!${NC}"; exit 0 ;;
        *) echo "Pilihan tidak valid"; sleep 1 ;;
    esac
done
