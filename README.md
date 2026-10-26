# 9Router — Podman

Image Podman untuk [decolua/9router](https://github.com/decolua/9router): router AI
(endpoint kompatibel OpenAI/Anthropic) + dashboard web, port **20128**.

> Packaging tidak resmi untuk Podman. Repo ini hanya berisi `Containerfile` + dokumentasi;
> source 9router di-clone dari upstream saat build. Lisensi aplikasi: MIT (lihat upstream).

Folder ini berisi semua yang dibutuhkan untuk build dan menjalankan container
secara manual dengan `podman run` — tanpa compose.

```text
/mnt/varkir/Podman/9router/
├── Containerfile      # build image (clone source dari GitHub saat build)
├── build.sh           # build + tag versi + upload ke ghcr.io/varkir/9router
├── entrypoint.sh      # urus izin /app/data, jalan sebagai root atau keep-id
├── .env.example       # template variabel lingkungan
├── .env               # rahasia Anda (JWT_SECRET, INITIAL_PASSWORD, ...) — jangan di-commit
├── data/              # data persisten → /app/data di container (db/data.sqlite, dll.)
├── README.md
└── AGENTS.md          # catatan untuk agent AI / maintainer
```

---

## 1. Server ini (Debian 13, Podman rootless, network `varkir`)

| Item         | Nilai                                        |
|--------------|----------------------------------------------|
| Image        | `ghcr.io/varkir/9router:latest`              |
| Container    | `9router`                                    |
| Network      | `varkir` (10.20.0.0/24, gateway 10.20.0.1)   |
| IP container | `10.20.0.13`                                 |
| Port         | `20128` (dipublish juga ke host)             |
| Data         | `/mnt/varkir/Podman/9router/data` → `/app/data` |

### Build & upload ke GitHub Packages

```bash
cd /mnt/varkir/Podman/9router
./build.sh
```

`build.sh` mengambil commit terbaru `decolua/9router`, membaca versinya dari
`package.json`, build image, lalu memberi tag dan meng-upload ke
[ghcr.io/varkir/9router](https://github.com/varkir/9router/pkgs/container/9router):

| Tag | Contoh | Keterangan |
|-----|--------|------------|
| `latest` | `ghcr.io/varkir/9router:latest` | Build terakhir dari branch `master` |
| `<versi>` | `ghcr.io/varkir/9router:0.5.111` | Versi 9router upstream |
| `<versi>-<sha>` | `ghcr.io/varkir/9router:0.5.111-3a978a6` | Versi + commit upstream (tidak berubah) |

Tag dibuat langsung dengan nama `ghcr.io/varkir/9router:*` (juga saat `PUSH=0`), jadi perintah run di bawah
langsung memakai hasil build terbaru.

```bash
PUSH=0 ./build.sh                    # build saja, tanpa upload
NINEROUTER_REF=v0.5.109 ./build.sh   # build tag tertentu (tag latest tidak disentuh)
./build.sh --no-cache                # argumen tambahan diteruskan ke podman build
```

Upload butuh login sekali dengan token GitHub yang punya izin `write:packages`:

```bash
podman login ghcr.io -u varkir
```

Build manual tanpa script juga bisa. `--format docker` wajib agar `HEALTHCHECK`
ikut tersimpan di image:

```bash
podman build --format docker -t ghcr.io/varkir/9router:latest .
```

### Siapkan `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env   # isi JWT_SECRET, INITIAL_PASSWORD, API_KEY_SECRET, MACHINE_ID_SALT
```

Contoh membuat nilai acak: `openssl rand -hex 32`.

> **Penting:** tanpa `INITIAL_PASSWORD`, 9Router memakai password default `123456`
> dan **menolak login dari mesin lain** sampai password diganti dari localhost.
> Karena container diakses lewat jaringan, isi `INITIAL_PASSWORD`.

### Jalankan

```bash
podman run -d \
  --name 9router \
  --network varkir \
  --ip 10.20.0.13 \
  -p 20128:20128 \
  --userns=keep-id \
  --env-file /mnt/varkir/Podman/9router/.env \
  -v /mnt/varkir/Podman/9router/data:/app/data:Z \
  --restart always \
  ghcr.io/varkir/9router:latest
```

- `--userns=keep-id` → uid 1000 di container = user Anda di host, jadi file di
  `data/` tetap milik Anda (bukan uid subordinate seperti 100999).
- `:Z` → label SELinux (diabaikan otomatis di Debian/Arch tanpa SELinux).
- Dari container lain di `varkir`: `http://10.20.0.13:20128` atau `http://9router:20128`.
- Dari host / LAN: `http://localhost:20128` atau `http://<ip-server>:20128`.
  Di Podman rootless, IP 10.20.0.x hidup di namespace jaringan rootless sehingga
  host tidak bisa langsung menjangkau 10.20.0.13 — karena itu port tetap dipublish.

Cek:

```bash
podman ps --filter name=9router
podman logs -f 9router
podman healthcheck run 9router && echo sehat
curl -s http://localhost:20128/api/health
```

Endpoint API untuk klien (Claude Code, Codex, Cursor, dll.): `http://<host>:20128/v1`.
Setiap klien yang bukan localhost **wajib** mengirim API key 9router (`Authorization: Bearer sk-...`).
Contoh OpenWebUI (satu network `varkir`): Admin Settings → Connections → OpenAI API →
URL `http://10.20.0.13:20128/v1`, Key = API key dari dashboard 9router.

### Auto-start setelah reboot (rootless)

`--restart always` hanya dihormati setelah reboot bila layanan berikut aktif
(`podman-restart.service` hanya menyalakan container dengan `restart-policy=always`,
**bukan** `unless-stopped`):

```bash
systemctl --user enable --now podman-restart.service
sudo loginctl enable-linger "$USER"
```

### Kelola container

```bash
podman stop 9router
podman start 9router
podman restart 9router
podman rm -f 9router          # hapus container (data di ./data tetap aman)
podman exec -it 9router sh    # masuk shell
```

### Update ke versi terbaru

```bash
cd /mnt/varkir/Podman/9router
tar czf ~/9router-backup-$(date +%F).tar.gz data .env   # backup dulu
./build.sh --pull                                        # build + upload ke GHCR
podman rm -f 9router
# jalankan lagi perintah "podman run" di atas
podman image prune -f
```

Kalau upstream belum punya commit baru, `build.sh` memakai cache sehingga
selesai dalam hitungan detik. Rollback: jalankan ulang container dengan tag
versi lama, misalnya `ghcr.io/varkir/9router:0.5.111-3a978a6`.

### Backup

```bash
podman stop 9router
tar czf ~/9router-backup-$(date +%F).tar.gz -C /mnt/varkir/Podman/9router data .env
podman start 9router
```

---

## 2. Instal Podman di distro / OS lain

| OS | Perintah |
|----|----------|
| Debian / Ubuntu / Mint | `sudo apt update && sudo apt install -y podman` |
| Arch / Manjaro / EndeavourOS | `sudo pacman -S --needed podman` |
| Fedora / RHEL / Rocky / Alma | `sudo dnf install -y podman` |
| openSUSE | `sudo zypper install -y podman` |
| Alpine | `sudo apk add podman` (lalu `rc-update add cgroups`) |
| Windows 10/11 | `winget install -e --id RedHat.Podman` (atau Podman Desktop), lalu `podman machine init` dan `podman machine start` |
| macOS | `brew install podman`, lalu `podman machine init` dan `podman machine start` |

Rootless di Linux butuh entri subuid/subgid (biasanya otomatis dibuat):

```bash
grep "$USER" /etc/subuid /etc/subgid || sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
```

---

## 3. Menjalankan di mesin lain

Langkah umumnya sama: ambil image → buat `.env` → buat network → `podman run`.
Ganti path data sesuai mesin Anda.

### Ambil image siap pakai (tanpa build)

Image `linux/amd64` tersedia di GitHub Packages, jadi mesin lain tidak perlu build:

```bash
podman pull ghcr.io/varkir/9router:latest
```

Semua perintah `podman run` di README ini memakai `ghcr.io/varkir/9router:latest`,
sama dengan server. Tetap butuh `.env`: salin `.env.example` dari repo ini.
Untuk mesin ARM (Raspberry Pi, Mac Apple Silicon), build sendiri dengan `podman build`.

### Buat network `varkir` (kalau belum ada)

```bash
podman network create --subnet 10.20.0.0/24 --gateway 10.20.0.1 varkir
```

Kalau tidak butuh IP tetap, hapus saja `--network`/`--ip` dari perintah run.

### Linux apa pun (Debian, Ubuntu, Arch, Fedora, ...)

```bash
git clone https://github.com/varkir/9router.git ~/9router
cd ~/9router
cp .env.example .env && chmod 600 .env && nano .env
mkdir -p data
podman pull ghcr.io/varkir/9router:latest      # atau build: podman build --format docker -t ghcr.io/varkir/9router:latest .

podman run -d \
  --name 9router \
  --network varkir --ip 10.20.0.13 \
  -p 20128:20128 \
  --userns=keep-id \
  --env-file "$PWD/.env" \
  -v "$PWD/data:/app/data:Z" \
  --restart always \
  ghcr.io/varkir/9router:latest
```

Podman **rootful** (`sudo podman ...`): hapus `--userns=keep-id`; entrypoint akan
otomatis `chown` folder data ke user `node` lalu turun hak akses.

### Windows (PowerShell, Podman Desktop / `podman machine`)

```powershell
cd C:\podman\9router
Copy-Item .env.example .env ; notepad .env
New-Item -ItemType Directory -Force data | Out-Null
podman pull ghcr.io/varkir/9router:latest
podman network create --subnet 10.20.0.0/24 --gateway 10.20.0.1 varkir

podman run -d `
  --name 9router `
  --network varkir --ip 10.20.0.13 `
  -p 20128:20128 `
  --env-file C:\podman\9router\.env `
  -v C:\podman\9router\data:/app/data `
  --restart always `
  ghcr.io/varkir/9router:latest
```

CMD (cmd.exe): ganti backtick `` ` `` dengan `^`.
Di Windows/macOS jangan pakai `--userns=keep-id` dan `:Z` — entrypoint sudah
mengurus izin folder. Buka `http://localhost:20128`.

> Tip Windows: simpan data di filesystem VM (named volume) untuk performa SQLite
> yang lebih baik: `-v 9router-data:/app/data`.

### macOS

Mac Intel bisa langsung memakai image GHCR. Mac Apple Silicon (arm64) perlu
build dulu dengan nama yang sama, lalu jalankan perintah di bawah tanpa diubah:
`podman build --format docker -t ghcr.io/varkir/9router:latest .`

```bash
podman run -d --name 9router \
  --network varkir --ip 10.20.0.13 -p 20128:20128 \
  --env-file "$PWD/.env" -v "$PWD/data:/app/data" \
  --restart always ghcr.io/varkir/9router:latest
```

---

## 4. Variabel lingkungan

| Variabel | Default | Keterangan |
|----------|---------|------------|
| `JWT_SECRET` | acak per start | **Isi** agar sesi login tidak hilang saat restart |
| `INITIAL_PASSWORD` | `123456` | Password awal dashboard; wajib untuk akses remote |
| `API_KEY_SECRET` | — | Secret untuk API key endpoint |
| `MACHINE_ID_SALT` | — | Salt machine-id |
| `REQUIRE_API_KEY` | `false` | Wajibkan API key untuk `/v1` |
| `AUTH_COOKIE_SECURE` | `false` | `true` bila di belakang HTTPS reverse proxy |
| `ENABLE_REQUEST_LOGS` | `false` | Log request/response |
| `BASE_URL` | `http://localhost:20128` | URL instance dari dalam container |
| `SEARXNG_URL` | — | Mis. `http://10.20.0.3:8080/search` (SearXNG di varkir) |
| `HEADROOM_URL` | — | Sidecar Headroom, mis. `http://headroom:8787` |
| `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY` | — | Proxy keluar ke provider |
| `DATA_DIR` | `/app/data` | Sudah diset di image, jangan diubah |
| `PORT` | `20128` | Port di dalam container |

Daftar lengkap: `.env.example` di repo upstream.

---

## 5. Troubleshooting

| Gejala | Solusi |
|--------|--------|
| `Error: ... ip 10.20.0.13 ... already allocated` | IP dipakai container lain: `podman network inspect varkir` |
| `network varkir not found` | Buat network (bagian 3) |
| Log: `/app/data tidak bisa ditulis` | Linux rootless: tambah `--userns=keep-id`, atau ganti `:Z` → `:Z,U` |
| File di `data/` milik uid aneh (100999) | Container pernah jalan tanpa `keep-id`: `podman unshare chown -R 0:0 data` lalu jalankan ulang dengan `--userns=keep-id` |
| Login ditolak "Default password must be changed" | Isi `INITIAL_PASSWORD` di `.env`, lalu `podman rm -f 9router` dan run ulang |
| Container hilang setelah reboot | Aktifkan `podman-restart.service` + linger (bagian 1) |
| Build gagal di `npm install` | Ulangi; atau pakai mirror: `--build-arg NPM_REGISTRY=https://registry.npmmirror.com/` |
| Port 20128 sudah dipakai | Ganti sisi host: `-p 20129:20128` |
| `podman pull ghcr.io/varkir/9router` → `unauthorized` / `denied` | Package masih private: login dulu (`podman login ghcr.io`) atau jadikan public di GitHub → Packages → 9router → Package settings |
| `build.sh` gagal saat push: `denied` / `unauthorized` | `podman login ghcr.io -u varkir` dengan token ber-izin `write:packages` |
| `{"error":"API key required for remote API access"}` (401) | Semua akses `/v1` dari luar localhost (OpenWebUI, LAN, container lain) wajib pakai API key: buat/salin di dashboard 9router (menu API Keys), lalu isi sebagai *API Key* di klien |
