#!/bin/sh
# Entrypoint 9Router.
#  - Jalan sebagai root  : betulkan kepemilikan /app/data lalu turun ke user node.
#  - Jalan sebagai non-root (mis. --userns=keep-id): langsung exec, tanpa chown.
set -e

DATA_DIR="${DATA_DIR:-/app/data}"
mkdir -p "$DATA_DIR" "${HOME:-/app/data-home}" 2>/dev/null || true

if [ "$(id -u)" = "0" ]; then
  chown -R node:node "$DATA_DIR" "${HOME:-/app/data-home}" 2>/dev/null || true
  exec su-exec node "$@"
fi

if [ ! -w "$DATA_DIR" ]; then
  echo "[entrypoint] PERINGATAN: $DATA_DIR tidak bisa ditulis oleh uid $(id -u)." >&2
  echo "[entrypoint] Pakai --userns=keep-id (Linux rootless) atau tambahkan :U pada -v." >&2
fi

exec "$@"
