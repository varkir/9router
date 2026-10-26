# Containerfile 9Router (https://github.com/decolua/9router) untuk Podman.
#
# Source di-clone langsung dari GitHub saat build, jadi build context cukup
# folder ini saja:
#
#   ./build.sh                       (disarankan: kunci commit + tag + push GHCR)
#   podman build --format docker -t ghcr.io/varkir/9router:latest .
#   podman build --format docker --build-arg NINEROUTER_REF=v0.5.109 -t ghcr.io/varkir/9router:0.5.109 .
#
# NINEROUTER_COMMIT (sha lengkap) mengunci source ke satu commit. build.sh
# mengisinya dari "git ls-remote", jadi cache layer clone otomatis batal saat
# upstream punya commit baru dan tetap dipakai bila belum berubah.
#
# Berbeda dengan Dockerfile upstream, image ini:
#   - bisa jalan sebagai root (lalu turun ke user node) ATAU langsung sebagai
#     uid 1000 (--userns=keep-id di Podman rootless) tanpa error su-exec;
#   - punya HEALTHCHECK ke /api/health.

ARG NODE_IMAGE=docker.io/library/node:22-alpine
ARG NPM_REGISTRY=https://registry.npmjs.org/

# ---------------------------------------------------------------- source ----
FROM ${NODE_IMAGE} AS source
ARG NINEROUTER_REPO=https://github.com/decolua/9router.git
ARG NINEROUTER_REF=
ARG NINEROUTER_COMMIT=
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 ${NINEROUTER_REF:+--branch "$NINEROUTER_REF"} "${NINEROUTER_REPO}" . \
 && if [ -n "$NINEROUTER_COMMIT" ] && [ "$(git rev-parse HEAD)" != "$NINEROUTER_COMMIT" ]; then \
      git fetch --depth 1 origin "$NINEROUTER_COMMIT" && git checkout -q FETCH_HEAD; \
    fi \
 && git rev-parse HEAD > /src/.git-commit \
 && rm -rf .git

# --------------------------------------------------------------- builder ----
FROM ${NODE_IMAGE} AS builder
ARG NPM_REGISTRY
RUN apk add --no-cache python3 make g++ linux-headers
WORKDIR /app

COPY --from=source /src/package.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm install \
      --registry="${NPM_REGISTRY}" \
      --fetch-retries=5 \
      --fetch-retry-factor=2 \
      --fetch-retry-mintimeout=10000 \
      --fetch-retry-maxtimeout=120000 \
      --fetch-timeout=300000

COPY --from=source /src/ ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---------------------------------------------------------------- runner ----
FROM ${NODE_IMAGE} AS runner
WORKDIR /app

RUN apk add --no-cache su-exec ffmpeg tini

ENV NODE_ENV=production \
    PORT=20128 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1 \
    DATA_DIR=/app/data \
    HOME=/app/data-home

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/custom-server.js ./custom-server.js
COPY --from=builder /app/open-sse ./open-sse
# MITM berjalan sebagai proses terpisah; file tracing Next tidak menyertakannya.
COPY --from=builder /app/src/mitm ./src/mitm
# Modul yang di-load secara dinamis dan sering terlewat oleh tracing.
COPY --from=builder /app/node_modules/node-forge ./node_modules/node-forge
COPY --from=builder /app/node_modules/next ./node_modules/next
COPY --from=builder /app/node_modules/sql.js ./node_modules/sql.js
COPY --from=builder /app/node_modules/node-machine-id ./node_modules/node-machine-id
COPY --from=source /src/.git-commit ./.git-commit

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && mkdir -p /app/data /app/data-home \
 && chown -R node:node /app

ARG NINEROUTER_REF=
ARG NINEROUTER_COMMIT=
ARG IMAGE_VERSION=
ARG IMAGE_SOURCE=https://github.com/varkir/9router
# image.source dipakai GHCR untuk menautkan package ke repo varkir/9router.
LABEL org.opencontainers.image.title="9router" \
      org.opencontainers.image.description="9Router AI router + dashboard untuk Podman (packaging tidak resmi decolua/9router)" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.url="https://github.com/decolua/9router" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${NINEROUTER_COMMIT}"

VOLUME ["/app/data"]
EXPOSE 20128

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/api/health" >/dev/null || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["node", "custom-server.js"]
