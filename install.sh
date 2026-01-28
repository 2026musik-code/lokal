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

# Log & PID Files
LOG_XRAY="$LOG_DIR/xray.log"
LOG_CF="$LOG_DIR/cloudflared.log"
PID_XRAY="$LOG_DIR/xray.pid"
PID_CF="$LOG_DIR/cloudflared.pid"

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
        # Tambahkan iproute2 untuk ss
        packages=("curl" "wget" "zip" "jq" "openssl" "util-linux" "procps" "iproute2")
        for pkg in "${packages[@]}"; do
            if ! command -v "$pkg" &> /dev/null && ! pkg list-installed "$pkg" &> /dev/null; then
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
        echo -e "${GREEN}[+] Xray ditemukan di $XRAY_BIN. Melewati unduhan.${NC}"
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
        echo -e "${GREEN}[+] Cloudflared ditemukan di $CF_BIN. Melewati unduhan.${NC}"
    else
        echo -e "${YELLOW}[*] Mendownload Cloudflared...${NC}"
        wget -q --show-progress "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" -O "$CF_BIN"
        chmod +x "$CF_BIN"
        echo -e "${GREEN}[+] Cloudflared berhasil diinstall.${NC}"
    fi
}

# Generate/Reset Config Xray
generate_xray_config() {
    local uuid=$1
    local loglevel=${2:-"info"} # Default loglevel info, bisa di-override

    echo -e "${YELLOW}[*] Membuat konfigurasi Xray (Port 8080, VLESS WS)...${NC}"
    # Listen 0.0.0.0 agar bind ke semua interface, antisipasi routing internal
    cat <<EOF > "$XRAY_CONFIG"
{
  "log": {
    "loglevel": "$loglevel"
  },
  "inbounds": [
    {
      "port": 8080,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless",
          "headers": {
            "Host": "127.0.0.1"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
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

        generate_xray_config "$UUID" "info"

        echo -e "${GREEN}[+] Konfigurasi disimpan!${NC}"
        sleep 2
    fi
}

# Helper Check Process
is_running() {
    local pid_file=$1
    local name=$2
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null; then
            return 0
        fi
    fi
    # Fallback to pgrep if PID file fails but process exists
    if pgrep -f "$name" > /dev/null; then
        return 0
    fi
    return 1
}

# Start Tunnel
start_tunnel() {
    source "$USER_DATA"

    # Cek Xray
    if is_running "$PID_XRAY" "xray"; then
        echo -e "${RED}[!] Xray sudah berjalan.${NC}"
    else
        echo -e "${YELLOW}[*] Menjalankan Xray...${NC}"
        cd "$BIN_DIR" || exit
        nohup ./xray run -c "$XRAY_CONFIG" > "$LOG_XRAY" 2>&1 &
        echo $! > "$PID_XRAY"

        sleep 1
        if ! is_running "$PID_XRAY" "xray"; then
            echo -e "${RED}[!] Gagal menjalankan Xray. Cek log error.${NC}"
        fi
    fi

    # Cek Cloudflared
    if is_running "$PID_CF" "cloudflared"; then
         echo -e "${RED}[!] Cloudflared sudah berjalan.${NC}"
    else
        echo -e "${YELLOW}[*] Menjalankan Cloudflared...${NC}"
        cd "$BIN_DIR" || exit

        # Cek integritas binary
        if ! ./cloudflared --version > /dev/null 2>&1; then
             echo -e "${RED}[!] Binary cloudflared rusak atau tidak kompatibel dengan device ini.${NC}"
             echo -e "${YELLOW}[*] Mencoba download ulang...${NC}"
             rm "$CF_BIN"
             install_binaries
             cd "$BIN_DIR" || exit
        fi

        > "$LOG_CF"
        touch "$LOG_CF"
        chmod 644 "$LOG_CF"

        # Tambahkan --protocol http2 untuk stabilitas lebih baik
        nohup ./cloudflared tunnel run --protocol http2 --token "$TOKEN" > "$LOG_CF" 2>&1 &
        echo $! > "$PID_CF"

        sleep 5

        if [ ! -s "$LOG_CF" ]; then
            echo -e "${RED}[!] Log Cloudflared kosong. Kemungkinan masalah permission atau binary crash.${NC}"
            echo -e "${YELLOW}[*] Mencoba menjalankan diagnostik (Direct Output):${NC}"
            echo -e "${CYAN}------------------------------------------------${NC}"
            ./cloudflared tunnel run --protocol http2 --token "$TOKEN" &
            CF_TEST_PID=$!
            sleep 5
            kill $CF_TEST_PID 2>/dev/null
            echo -e "${CYAN}------------------------------------------------${NC}"
        fi

        if grep -q "Cannot determine default configuration path" "$LOG_CF"; then
            echo -e "${YELLOW}[!] Warning: Konfigurasi default tidak ditemukan (Normal jika pakai token).${NC}"
        fi

        if grep -q "Unauthorized: Run \`cloudflared tunnel login\`" "$LOG_CF"; then
             echo -e "${RED}[!] Error: Token Salah atau Expired! Silakan ganti token.${NC}"
             stop_tunnel > /dev/null
             return
        fi

        if ! is_running "$PID_CF" "cloudflared"; then
             echo -e "${RED}[!] Cloudflared gagal berjalan. Cek menu Log.${NC}"
        else
             echo -e "${CYAN}[INFO] Pastikan di Dashboard Cloudflare Zero Trust:${NC}"
             echo -e "${CYAN}       Service: HTTP  |  URL: 127.0.0.1:8080${NC}"
             echo -e "${CYAN}       (Jangan pakai localhost untuk menghindari isu IPv6)${NC}"
        fi
    fi

    sleep 1
    echo -e "${GREEN}[+] Tunnel berhasil dijalankan!${NC}"
    if [[ "${FUNCNAME[1]}" != "enable_debug_mode" && "${FUNCNAME[1]}" != "repair_config" ]]; then
        read -p "Tekan Enter untuk kembali ke menu..."
    fi
}

# Stop Tunnel
stop_tunnel() {
    echo -e "${YELLOW}[*] Menghentikan proses...${NC}"

    if [ -f "$PID_XRAY" ]; then
        kill $(cat "$PID_XRAY") 2>/dev/null
        rm "$PID_XRAY"
    else
        pkill -f "xray"
    fi

    if [ -f "$PID_CF" ]; then
        kill $(cat "$PID_CF") 2>/dev/null
        rm "$PID_CF"
    else
        pkill -f "cloudflared"
    fi

    echo -e "${GREEN}[+] Semua proses dimatikan.${NC}"
    if [[ "${FUNCNAME[1]}" != "change_token" && "${FUNCNAME[1]}" != "repair_config" && "${FUNCNAME[1]}" != "enable_debug_mode" ]]; then
        read -p "Tekan Enter untuk kembali ke menu..."
    fi
}

# Ambil Link
get_link() {
    source "$USER_DATA"
    # Tambahkan sni=domain untuk memastikan SNI terkirim
    LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=%2Fvless&sni=${DOMAIN}#Termux-VLESS"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}VLESS LINK:${NC}"
    echo -e "${LINK}"
    echo -e "${CYAN}==============================================================${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Change Token
change_token() {
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}GANTI TOKEN CLOUDFLARE${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "Token saat ini: ${TOKEN:0:10}......${TOKEN: -5}"
    echo ""
    read -p "Masukkan Token Baru: " NEW_TOKEN

    if [ -z "$NEW_TOKEN" ]; then
        echo -e "${RED}[!] Token tidak boleh kosong.${NC}"
    else
        sed -i "s|TOKEN=\".*\"|TOKEN=\"$NEW_TOKEN\"|" "$USER_DATA"
        echo -e "${GREEN}[+] Token berhasil diupdate!${NC}"

        if is_running "$PID_CF" "cloudflared"; then
            echo -e "${YELLOW}[*] Me-restart Cloudflare Tunnel...${NC}"
            stop_tunnel
            start_tunnel
        fi
    fi
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Repair Config
repair_config() {
    source "$USER_DATA"
    echo -e "${YELLOW}[*] Memperbaiki/Reset Konfigurasi Xray...${NC}"
    stop_tunnel
    generate_xray_config "$UUID" "info"
    echo -e "${GREEN}[+] Config Xray berhasil direset dengan setting optimal (0.0.0.0, Sniffing, Log Info).${NC}"
    echo -e "${YELLOW}[*] Me-restart Tunnel...${NC}"
    start_tunnel
}

# Enable Debug Mode
enable_debug_mode() {
    source "$USER_DATA"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}AKTIFKAN MODE DEBUG EKSTRIM${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "Ini akan merubah log level Xray ke 'debug' dan merestart tunnel."
    echo -e "Anda akan melihat semua detail koneksi."
    echo ""

    stop_tunnel
    generate_xray_config "$UUID" "debug"
    echo -e "${GREEN}[+] Config Xray diupdate ke Debug Mode.${NC}"

    # Jalankan tunnel
    start_tunnel

    echo -e "${YELLOW}[*] Menampilkan Log Xray (Tekan Ctrl+C untuk keluar):${NC}"
    # Gunakan trap untuk menangkap Ctrl+C dan kembali ke menu
    trap 'echo -e "\n${GREEN}[+] Keluar dari mode pantau log.${NC}"; return' SIGINT
    tail -f "$LOG_XRAY"
    trap - SIGINT
}

# Diagnosis
run_diagnostics() {
    clear
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}DIAGNOSA MASALAH KONEKSI${NC}"
    echo -e "${CYAN}==============================================================${NC}"

    echo -e "${GREEN}1. Cek Port 8080 (Xray):${NC}"
    if ss -lnt | grep -q ":8080"; then
        echo -e "   [OK] Port 8080 sedang listening."
    else
        echo -e "   ${RED}[FAIL] Port 8080 tidak aktif! Xray mungkin mati.${NC}"
    fi
    echo ""

    echo -e "${GREEN}2. Cek Koneksi Masuk (Log Xray):${NC}"
    echo -e "   Menampilkan 10 baris terakhir akses log:"
    if [ -f "$LOG_XRAY" ]; then
        # Coba cari log accepted/rejected
        if grep -E "accepted|rejected" "$LOG_XRAY" > /dev/null; then
             echo -e "${YELLOW}Ditemukan aktivitas:${NC}"
             grep -E "accepted|rejected" "$LOG_XRAY" | tail -n 10

             if grep -q "rejected" "$LOG_XRAY"; then
                 echo -e "${RED}[!] WARNING: Ada koneksi 'rejected'. Cek UUID atau Path.${NC}"
             fi
        else
             echo -e "${YELLOW}Belum ada aktivitas koneksi (accepted/rejected).${NC}"
             tail -n 5 "$LOG_XRAY"
        fi
    else
        echo -e "   ${RED}[!] File log tidak ditemukan.${NC}"
    fi
    echo ""

    echo -e "${GREEN}3. Cek Status Proses:${NC}"
    if is_running "$PID_XRAY" "xray"; then
        echo -e "   [OK] Xray berjalan (PID: $(cat $PID_XRAY))"
    else
        echo -e "   ${RED}[FAIL] Xray MATI${NC}"
    fi
    if is_running "$PID_CF" "cloudflared"; then
        echo -e "   [OK] Cloudflared berjalan (PID: $(cat $PID_CF))"
    else
        echo -e "   ${RED}[FAIL] Cloudflared MATI${NC}"
    fi

    echo -e "${CYAN}==============================================================${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Tutorial
show_help() {
    clear
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}PANDUAN SETTING CLOUDFLARE ZERO TRUST${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${GREEN}1. Login ke Dashboard:${NC}"
    echo -e "   Buka https://one.dash.cloudflare.com/ dan login."
    echo ""
    echo -e "${GREEN}2. Masuk ke Menu Tunnels:${NC}"
    echo -e "   Pilih 'Networks' -> 'Tunnels'."
    echo ""
    echo -e "${GREEN}3. Pilih/Buat Tunnel:${NC}"
    echo -e "   - Klik nama tunnel yang tokennya Anda pakai di sini."
    echo -e "   - Klik 'Configure'."
    echo ""
    echo -e "${GREEN}4. Setting Public Hostname (PENTING!):${NC}"
    echo -e "   - Masuk ke tab 'Public Hostname'."
    echo -e "   - Klik 'Add a public hostname'."
    echo -e "   - ${YELLOW}Subdomain:${NC} Isi bebas (contoh: vless)."
    echo -e "   - ${YELLOW}Domain:${NC} Pilih domain Anda ($DOMAIN)."
    echo -e "   - ${YELLOW}Service:${NC} Pilih ${CYAN}HTTP${NC}."
    echo -e "   - ${YELLOW}URL:${NC} Ketik ${CYAN}127.0.0.1:8080${NC}."
    echo ""
    echo -e "${RED}KENAPA 127.0.0.1:8080?${NC}"
    echo -e "Menggunakan 'localhost' terkadang dianggap IPv6 (::1) oleh sistem."
    echo -e "Gunakan '127.0.0.1' agar pasti mengarah ke Xray yang kita install."
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
    if is_running "$PID_XRAY" "xray"; then
        XRAY_STATUS="${GREEN}ON${NC}"
    else
        XRAY_STATUS="${RED}OFF${NC}"
    fi

    if is_running "$PID_CF" "cloudflared"; then
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
    echo -e "[4] Ganti Token Cloudflare"
    echo -e "[5] Cek Log Error"
    echo -e "[6] Update Script (Dari Repo)"
    echo -e "[7] Refresh Status"
    echo -e "[8] Update/Re-install (Hapus Data)"
    echo -e "[9] Perbaiki Konfigurasi Xray (Reset)"
    echo -e "[10] Diagnosa Masalah"
    echo -e "[11] Mode Debug (Log Detail)"
    echo -e "[?] Tutorial & Cara Setting"
    echo -e "[0] Keluar"
    echo -e "${CYAN}==============================================================${NC}"
    read -p "Pilih menu: " choice

    case $choice in
        1) start_tunnel ;;
        2) stop_tunnel ;;
        3) get_link ;;
        4) change_token ;;
        5) view_logs ;;
        6) update_script ;;
        7) continue ;;
        8) reinstall ;;
        9) repair_config ;;
        10) run_diagnostics ;;
        11) enable_debug_mode ;;
        "?") show_help ;;
        0) echo -e "${GREEN}Terima kasih!${NC}"; exit 0 ;;
        *) echo "Pilihan tidak valid"; sleep 1 ;;
    esac
done
