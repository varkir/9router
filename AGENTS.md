# AGENTS.md — 9Router (Podman)

Panduan untuk agent AI / maintainer yang bekerja di folder ini.
Dokumentasi pengguna ada di `README.md`.

## Tujuan

Folder ini membungkus [decolua/9router](https://github.com/decolua/9router) (Next.js 16,
Node 22) menjadi image Podman dan menjalankannya secara **manual** dengan `podman run`
(bukan compose, bukan Quadlet) di server Debian 13, Podman rootless.

## Fakta deployment (jangan diubah tanpa diminta)

- Image: `localhost/9router:latest`, container: `9router`
- Network: `varkir` (bridge 10.20.0.0/24, gw 10.20.0.1, DNS aktif), IP: `10.20.0.13`
- Port: `20128` (container) dipublish ke host `20128`
- Data: `/mnt/varkir/Podman/9router/data` → `/app/data` (`DATA_DIR`)
- Rahasia: `/mnt/varkir/Podman/9router/.env` (mode 600) — **jangan dibaca ke output, di-commit, atau dikirim ke mana pun**
- Mode user: `--userns=keep-id` (uid host 1000 = user `node` uid 1000 di image)
- Restart: `--restart always` + `podman-restart.service` (user) + linger aktif. Service ini hanya
  menyalakan `restart-policy=always`, jadi jangan pakai `unless-stopped`.
- IP lain di `varkir` yang sudah terpakai: 10.20.0.3 (searxng), 10.20.0.11 (voxcpm), 10.20.0.12 (voicestudio),
  10.20.0.70 (syncthing). Cek dengan `podman network inspect varkir` sebelum menambah container.

Perintah run kanonik (harus selalu sama dengan README.md bagian 1):

```bash
podman run -d --name 9router --network varkir --ip 10.20.0.13 -p 20128:20128 \
  --userns=keep-id --env-file /mnt/varkir/Podman/9router/.env \
  -v /mnt/varkir/Podman/9router/data:/app/data:Z \
  --restart always localhost/9router:latest
```

## File

| File | Isi |
|------|-----|
| `Containerfile` | Multi-stage: `source` (git clone `NINEROUTER_REF`) → `builder` (`npm install` + `next build`) → `runner` (standalone + tini + ffmpeg) |
| `entrypoint.sh` | Root → `chown` data lalu `su-exec node`; non-root → langsung `exec` |
| `.env.example` | Template env; `.env` asli tidak boleh di-commit |
| `.containerignore` | Mengecualikan `.env` dan `data/` dari build context |
| `.gitignore` | Mengecualikan `.env`, `data/`, backup `*.tar.gz` dari git (repo `git@github.com:varkir/9router.git`) |

## Aturan kerja

1. Source upstream **tidak** disalin ke folder ini; selalu di-clone saat build
   (`--build-arg NINEROUTER_REF=<branch|tag>`; kosong = branch default `master`). Jangan menambahkan source ke sini.
2. Build selalu dengan `--format docker` (kalau tidak, `HEALTHCHECK` dibuang Podman).
3. Jika upstream mengubah `Dockerfile`-nya (daftar `COPY` di stage runner, mis. modul
   `node_modules/*` tambahan yang tidak ter-trace), samakan stage `runner` di `Containerfile`.
   Cek: `https://github.com/decolua/9router/blob/master/Dockerfile`.
4. Jangan pernah menghapus atau menimpa `data/` (berisi `db/data.sqlite`, akun provider,
   API key). Backup dulu sebelum operasi berisiko.
5. Jangan mengubah IP/network/port tanpa permintaan eksplisit pengguna.
6. Dokumentasi untuk pengguna ditulis dalam Bahasa Indonesia, mengikuti gaya folder
   lain di `/mnt/varkir/Podman/` (mis. `voxcpm/run.sh`).
7. Setelah mengubah `Containerfile`/`entrypoint.sh`, verifikasi:
   ```bash
   podman build --format docker -t localhost/9router:latest .
   podman rm -f 9router && <perintah run kanonik>
   podman healthcheck run 9router
   curl -sf http://localhost:20128/api/health
   ls -ln data/   # pemilik harus uid 1000
   ```

## Catatan teknis upstream

- Health check: `GET /api/health`.
- Tanpa `INITIAL_PASSWORD`, password default `123456` dan login non-localhost ditolak
  (`src/app/api/auth/login/route.js`).
- Tanpa `JWT_SECRET`, sesi tidak bertahan setelah restart.
- `DATA_DIR` yang tidak bisa ditulis → app diam-diam fallback ke `~/.9router`
  (`src/lib/dataDir.js`), jadi data hilang saat container dihapus. Karena itu
  entrypoint memberi peringatan bila `/app/data` tidak writable; `HOME` diarahkan ke
  `/app/data-home`.
- Driver DB: `better-sqlite3` (optional) dengan fallback `sql.js` (wasm).
- Fitur browser/playwright mengunduh runtime ke `<DATA_DIR>/runtime` saat pertama dipakai.
