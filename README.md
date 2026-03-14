# Recon Automation — recon-automation-shofwan

Pipeline otomasi enumerasi subdomain dan deteksi host aktif menggunakan Bash, subfinder, httpx, dan anew.
Script ini mengotomasi proses reconnaissance untuk keperluan bug bounty dan penetration testing secara legal dan ethical sebagai metode pembelajaran. 


1. Membaca daftar domain dari `input/domains.txt`
2. Menjalankan **subfinder** untuk enumerasi subdomain
3. Menggunakan **anew** untuk deduplikasi data subdomain
4. Memfilter host yang aktif menggunakan **httpx**
5. Menyimpan hasil dan log secara terpisah

---

## Struktur Folder

```
recon-automation-shofwan/
├── input/
│   └── domains.txt          # Daftar domain target
├── output/
│   ├── all-subdomains.txt   # list subdomain
│   └── live.txt             # Host aktif
├── scripts/
│   └── recon-auto.sh        # Script bach recon executable
├── logs/
│   ├── progress.log         # Log progres per domain beserta timestamp
│   └── errors.log           # Log error dari masing-masing tool
└── README.md                # Penjelasan Project 
```

---

## Setup Environment

### 1. Install Go (jika belum ada)

```bash
sudo apt update && sudo apt install -y golang-go
go version
```

### 2. Tambahkan binary Go ke PATH

```bash
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
source ~/.bashrc
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.zshrc
source ~/.zshrc
```

### 3. Install pdtm (ProjectDiscovery Tool Manager)

```bash
go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest
pdtm -version 
```

### 4. Install Tools via pdtm

```bash
pdtm -i subfinder
pdtm -i httpx
```

### 5. Install anew

```bash
go install -v github.com/tomnomnom/anew@latest
anew --help 
```

### 6. Verifikasi Semua Tools

```bash
subfinder -version
httpx -version
which anew
```

---

## Cara Menjalankan Script

### Clone & Siapkan Repo

```bash
git clone https://github.com/shofwanshiddiq/recon-automation-shofwan.git
cd recon-automation-shofwan
```

### Buat Struktur Folder

```bash
mkdir -p input output scripts logs
```

### Jadikan Script Executable

```bash
chmod +x scripts/recon-auto.sh
```

### Run Bash

```bash
bash scripts/recon-auto.sh
```

---

## Buat Input.txt

**`input/domains.txt`:**
```
dropbox.com
shopify.com
atlassian.com
hackerone.com
zendesk.com
```
## Log Progress Recon

---

**`logs/progress.log`** (timestamp per domain):
```
2026-03-14 09:42:12 [INFO]    === Sesi recon baru dimulai ===
2026-03-14 09:42:12 [INFO]    Input: 6 domain dimuat dari /home/shofwan/recon-automation/input/domains.txt
2026-03-14 09:42:12 [INFO]    Pengecekan tool berhasil: subfinder
httpx
anew
2026-03-14 09:42:12 [INFO]    [1/6] subfinder berjalan untuk: dropbox.com
2026-03-14 09:42:43 [SUCCESS] subfinder OK untuk dropbox.com | total unik: 2156
2026-03-14 09:42:43 [INFO]    [2/6] subfinder berjalan untuk: shopify.com
2026-03-14 09:43:04 [SUCCESS] subfinder OK untuk shopify.com | total unik: 3546
2026-03-14 09:43:04 [INFO]    [3/6] subfinder berjalan untuk: atlassian.com
2026-03-14 09:46:06 [SUCCESS] subfinder OK untuk atlassian.com | total unik: 21176
2026-03-14 09:46:06 [INFO]    [4/6] subfinder berjalan untuk: hackerone.com
2026-03-14 09:46:11 [SUCCESS] subfinder OK untuk hackerone.com | total unik: 21192
2026-03-14 09:46:11 [INFO]    [5/6] subfinder berjalan untuk: zendesk.com
2026-03-14 09:56:12 [SUCCESS] subfinder OK untuk zendesk.com | total unik: 39580
2026-03-14 09:56:12 [SUCCESS] Fase 1 selesai. Total subdomain unik: 39580
2026-03-14 09:56:12 [INFO]    httpx memprobe 39580 subdomain
2026-03-14 09:56:13 [INFO]    === RINGKASAN AKHIR ===
2026-03-14 09:56:13 [INFO]    Subdomain unik : 39580
2026-03-14 09:56:13 [INFO]    Host aktif     : 0
2026-03-14 09:56:13 [INFO]    Pipeline recon selesai pada 2026-03-14 09:56:13
```

---

## Penjelasan Kode Script

### Bagian 0 — Strict Mode & Helper Warna

```bash
set -euo pipefail
```

| Flag | Fungsi |
|------|--------|
| `-e` | Script langsung berhenti jika ada perintah yang gagal |
| `-u` | Menampilkan error jika ada variabel yang belum didefinisikan |
| `-o pipefail` | Pipeline dianggap gagal jika salah satu perintah di dalamnya gagal |

Variabel warna (`RED`, `GREEN`, dll.) digunakan agar output di terminal lebih mudah dibaca.

---

### Bagian 1 — Konfigurasi Path

```bash
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
```

Script menggunakan path relatif berdasarkan lokasi script itu sendiri, sehingga dapat dijalankan dari direktori manapun tanpa perlu mengubah path secara manual (hardcode).

---

### Bagian 2 — Fungsi Helper Logging

Terdapat dua kategori fungsi logging:
- `log_info/log_success/log_warn/log_error` → **menulis ke file log** disertai timestamp
- `info/success/warn/error` → **menampilkan ke terminal** dengan warna berbeda

Fungsi `ts()` menghasilkan timestamp dengan format `YYYY-MM-DD HH:MM:SS`.

---

### Bagian 3 — Pengecekan Awal

`preflight_checks`

Melakukan validasi sebelum pipeline berjalan:
1. Membuat direktori `output/` dan `logs/` jika belum tersedia
2. Menghapus log lama agar setiap run menghasilkan log yang bersih
3. Memverifikasi bahwa `input/domains.txt` ada dan tidak kosong
4. Mengecek apakah `subfinder`, `httpx`, dan `anew` sudah terinstall


---

### Bagian 4 — Enumerasi Subdomain

`run_subfinder`

```bash
subfinder -d "$domain" -silent -timeout 30 2>>"$ERROR_LOG" \
  | anew "$ALL_SUBS" > /dev/null
```

- Melakukan loop per domain dari `domains.txt`
- `subfinder -d domain -silent` → mencari subdomain tanpa menampilkan banner
- Output di-pipe ke **`anew`** yang secara otomatis hanya menambahkan subdomain **baru** (yang belum ada di file) → deduplikasi otomatis
- `stderr` dari subfinder dialihkan ke `errors.log`
- Counter ditampilkan untuk memantau progres

---

### Bagian 5 — Filter Host Aktif

`run_httpx`

```bash
httpx -l "$ALL_SUBS" -title -status-code -silent \
      -threads 50 -timeout 10 -follow-redirects \
      2>>"$ERROR_LOG" | tee "$LIVE_FILE"
```

- Membaca `all-subdomains.txt` sebagai daftar input
- `-title` → mengambil judul halaman HTML
- `-status-code` → menampilkan kode status HTTP
- `-threads 50` → probing paralel untuk mempercepat proses
- `-follow-redirects` → mengikuti redirect HTTP 3xx secara otomatis
- `tee` → output ditampilkan di terminal **sekaligus** disimpan ke `live.txt`

---

### Bagian 6 — Laporan Ringkasan

`print_summary`

Menghitung dan menampilkan ringkasan akhir meliputi:
- Total subdomain unik yang ditemukan
- Total host aktif yang berhasil dideteksi
- Path lengkap ke semua file output

---
