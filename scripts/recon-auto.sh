
set -euo pipefail 
IFS=$'\n\t'
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';      RESET='\033[0m'

# Tentukan root project berdasarkan lokasi script, bukan dari mana script dipanggil
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

INPUT_FILE="$ROOT_DIR/input/domains.txt"
OUTPUT_DIR="$ROOT_DIR/output"
LOGS_DIR="$ROOT_DIR/logs"

ALL_SUBS="$OUTPUT_DIR/all-subdomains.txt"
LIVE_FILE="$OUTPUT_DIR/live.txt"
PROGRESS_LOG="$LOGS_DIR/progress.log"
ERROR_LOG="$LOGS_DIR/errors.log"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }   # fungsi untuk menghasilkan timestamp

log_info()    { echo -e "$(ts) [INFO]    $*" | tee -a "$PROGRESS_LOG"; }
log_success() { echo -e "$(ts) [SUCCESS] $*" | tee -a "$PROGRESS_LOG"; }
log_warn()    { echo -e "$(ts) [WARN]    $*" | tee -a "$PROGRESS_LOG"; }
log_error()   { echo -e "$(ts) [ERROR]   $*" | tee -a "$ERROR_LOG" >&2; }

# Fungsi print ke terminal saja (tidak ditulis ke file log)
info()    { echo -e "${CYAN}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✘]${RESET} $*"; }
banner()  { echo -e "\n${BOLD}${CYAN}$*${RESET}\n"; }

# 3. PENGECEKAN AWAL 
preflight_checks() {
    banner "=== RECON-AUTO.SH — Pipeline Recon Otomatis ==="

    # Buat direktori output dan logs jika belum ada
    mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"
    info "Direktori siap: output/ logs/"

    # Bersihkan log lama agar setiap run menghasilkan log yang baru
    : > "$PROGRESS_LOG"
    : > "$ERROR_LOG"
    log_info "=== Sesi recon baru dimulai ==="

    # Cek apakah file input ada dan tidak kosong
    if [[ ! -f "$INPUT_FILE" ]]; then
        error "File input tidak ditemukan: $INPUT_FILE"
        log_error "File input tidak ada: $INPUT_FILE"
        exit 1
    fi

    local domain_count
    domain_count=$(grep -cve '^\s*$' "$INPUT_FILE" || true)
    if [[ "$domain_count" -eq 0 ]]; then
        error "domains.txt kosong. Tambahkan minimal satu domain."
        log_error "domains.txt kosong"
        exit 1
    fi
    success "Ditemukan $domain_count domain di $INPUT_FILE"
    log_info "Input: $domain_count domain dimuat dari $INPUT_FILE"

    # Cek apakah semua tool yang dibutuhkan sudah terinstall
    local tools=("subfinder" "httpx" "anew")
    local missing=()
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Tool berikut tidak ditemukan: ${missing[*]}"
        log_error "Tool tidak ada: ${missing[*]}"
        echo ""
        warn "Install tool yang kurang dengan perintah:"
        warn "  pdtm -i subfinder httpx"
        warn "  go install -v github.com/tomnomnom/anew@latest"
        exit 1
    fi
    success "Semua tool ditemukan: ${tools[*]}"
    log_info "Pengecekan tool berhasil: ${tools[*]}"
}

# 4. ENUMERASI SUBDOMAIN
run_subfinder() {
    banner "[ FASE 1 ] Enumerasi Subdomain"

    # Kosongkan file output agar hasil tidak bercampur dengan run sebelumnya
    : > "$ALL_SUBS"

    local total_domains
    total_domains=$(grep -cve '^\s*$' "$INPUT_FILE" || true)
    local current=0

    while IFS= read -r domain || [[ -n "$domain" ]]; do
        # Lewati baris kosong dan baris komentar (diawali #)
        [[ -z "$domain" || "$domain" =~ ^# ]] && continue

        ((current++)) || true
        info "[$current/$total_domains] Memproses: ${BOLD}$domain${RESET}"
        log_info "[$current/$total_domains] subfinder berjalan untuk: $domain"

        # Jalankan subfinder lalu pipe hasilnya ke anew untuk deduplikasi
        if subfinder -d "$domain" \
                     -silent \
                     -timeout 30 \
                     2>>"$ERROR_LOG" \
           | anew "$ALL_SUBS" > /dev/null; then

            local count
            count=$(wc -l < "$ALL_SUBS" | tr -d ' ')
            success "  Selesai — total subdomain unik saat ini: $count"
            log_success "subfinder OK untuk $domain | total unik: $count"
        else
            warn "  subfinder gagal untuk $domain (cek errors.log)"
            log_warn "subfinder keluar dengan error untuk $domain"
        fi

    done < "$INPUT_FILE"

    local final_count
    final_count=$(wc -l < "$ALL_SUBS" | tr -d ' ')
    echo ""
    success "Fase 1 selesai — ${BOLD}$final_count subdomain unik${RESET} disimpan ke $ALL_SUBS"
    log_success "Fase 1 selesai. Total subdomain unik: $final_count"
}

# 5. FILTER HOST YANG AKTIF
run_httpx() {
    banner "[ FASE 2 ] Deteksi Host Aktif (httpx)"

    if [[ ! -s "$ALL_SUBS" ]]; then
        warn "all-subdomains.txt kosong — melewati fase httpx."
        log_warn "httpx dilewati: tidak ada subdomain untuk diprobe"
        return
    fi

    local sub_count
    sub_count=$(wc -l < "$ALL_SUBS" | tr -d ' ')
    info "Memprobe $sub_count subdomain untuk mencari host HTTP(S) yang aktif..."
    log_info "httpx memprobe $sub_count subdomain"
    if httpx -l "$ALL_SUBS" \
             -title \
             -status-code \
             -silent \
             -threads 50 \
             -timeout 10 \
             -follow-redirects \
             2>>"$ERROR_LOG" \
        | tee "$LIVE_FILE"; then

        local live_count
        live_count=$(wc -l < "$LIVE_FILE" | tr -d ' ')
        echo ""
        success "Fase 2 selesai — ${BOLD}$live_count host aktif${RESET} disimpan ke $LIVE_FILE"
        log_success "Fase 2 selesai. Host aktif: $live_count"
    else
        error "httpx mengalami error — cek logs/errors.log"
        log_error "httpx keluar dengan error"
    fi
}

# 6. PRINT SUMMARY
print_summary() {
    banner "=== RECON AUTOMATION TASK ==="

    local sub_count live_count
    sub_count=$(wc -l < "$ALL_SUBS"  2>/dev/null | tr -d ' ' || echo 0)
    live_count=$(wc -l < "$LIVE_FILE" 2>/dev/null | tr -d ' ' || echo 0)

    echo -e "  ${BOLD}Subdomain Unik     :${RESET} $sub_count"
    echo -e "  ${BOLD}Host Aktif         :${RESET} $live_count"
    echo -e "  ${BOLD}File Subdomain     :${RESET} $ALL_SUBS"
    echo -e "  ${BOLD}File Host Aktif    :${RESET} $LIVE_FILE"
    echo -e "  ${BOLD}Log Progres        :${RESET} $PROGRESS_LOG"
    echo -e "  ${BOLD}Log Error          :${RESET} $ERROR_LOG"
    echo ""

    log_info "=== RINGKASAN AKHIR ==="
    log_info "Subdomain unik : $sub_count"
    log_info "Host aktif     : $live_count"
    log_info "Pipeline recon selesai pada $(ts)"

    if [[ "$live_count" -gt 0 ]]; then
        success "Pipeline recon success"
    else
        warn "tidak ada host aktif. Cek errors.log untuk petunjuk."
    fi
}

# 7. MAIN SCRIPT
main() {
    preflight_checks   # cek direktori, file input, tools
    run_subfinder      # enumerasi subdomain
    run_httpx          # filter host aktif
    print_summary      # tampilkan ringkasan hasil akhir
}

main "$@"
