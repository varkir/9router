#!/usr/bin/env bash
# Build image 9Router lalu upload ke GitHub Packages (ghcr.io/varkir/9router).
#
#   ./build.sh                          -> build master terbaru + push :latest :<versi> :<versi>-<sha>
#   PUSH=0 ./build.sh                   -> build saja, tanpa upload
#   NINEROUTER_REF=v0.5.109 ./build.sh  -> build tag/branch tertentu (tanpa :latest)
#   ./build.sh --no-cache               -> argumen tambahan diteruskan ke "podman build"
#
# Tag dibuat langsung dengan nama GHCR, sehingga container di server (yang memakai
# ghcr.io/varkir/9router:latest) langsung memakai hasil build terbaru, juga saat PUSH=0.
#
# Upload butuh login sekali: podman login ghcr.io  (token dengan izin write:packages)
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

REGISTRY="${REGISTRY:-ghcr.io/varkir}"
IMAGE_NAME="${IMAGE_NAME:-9router}"
PUSH="${PUSH:-1}"
NINEROUTER_REPO="${NINEROUTER_REPO:-https://github.com/decolua/9router}"
NINEROUTER_REF="${NINEROUTER_REF:-}"
IMAGE_SOURCE="${IMAGE_SOURCE:-https://github.com/varkir/9router}"

# Commit upstream yang akan di-build (tag beranotasi -> commit di baliknya).
if [ -n "$NINEROUTER_REF" ]; then
  COMMIT="$(git ls-remote "$NINEROUTER_REPO" "refs/tags/$NINEROUTER_REF^{}" | cut -f1)"
  [ -n "$COMMIT" ] || COMMIT="$(git ls-remote "$NINEROUTER_REPO" "$NINEROUTER_REF" | head -1 | cut -f1)"
else
  COMMIT="$(git ls-remote "$NINEROUTER_REPO" HEAD | cut -f1)"
fi
[ -n "$COMMIT" ] || { echo "Ref '${NINEROUTER_REF:-HEAD}' tidak ditemukan di $NINEROUTER_REPO" >&2; exit 1; }
SHORT="${COMMIT:0:7}"

RAW="${NINEROUTER_REPO/github.com/raw.githubusercontent.com}"
VERSION="$(curl -fsSL "$RAW/$COMMIT/package.json" | sed -n 's/^  "version": "\(.*\)",$/\1/p')"
[ -n "$VERSION" ] || { echo "Gagal membaca versi dari package.json upstream" >&2; exit 1; }

# Urutan = urutan push. GHCR menampilkan tag yang terakhir di-push di halaman
# package ("docker pull ...:<tag>"), jadi latest selalu paling akhir.
tags=("$VERSION-$SHORT" "$VERSION")
[ -z "$NINEROUTER_REF" ] && tags+=(latest)

names=()
for t in "${tags[@]}"; do names+=(-t "$REGISTRY/$IMAGE_NAME:$t"); done

echo "+ 9router $VERSION (commit $SHORT) -> ${tags[*]}" >&2
podman build --format docker \
  --build-arg NINEROUTER_REPO="$NINEROUTER_REPO.git" \
  --build-arg NINEROUTER_REF="$NINEROUTER_REF" \
  --build-arg NINEROUTER_COMMIT="$COMMIT" \
  --build-arg IMAGE_VERSION="$VERSION" \
  --build-arg IMAGE_SOURCE="$IMAGE_SOURCE" \
  "${names[@]}" "$@" "$HERE"

if [ "$PUSH" = 1 ]; then
  for t in "${tags[@]}"; do
    echo "+ push $REGISTRY/$IMAGE_NAME:$t" >&2
    podman push "$REGISTRY/$IMAGE_NAME:$t"
  done
fi
