############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=cgr.dev/chainguard/node:latest-dev@sha256:617061855f341917060d95d164930fd949ed19e66fdc2918eabd2eefe2b29ae6
ARG RUST_IMAGE=cgr.dev/chainguard/rust:latest-dev@sha256:72490a904a8a150d7255515389f2117367a71fb79fd5485742cb139cb8a0dcd5
ARG NPM_VERSION=12.2.0
ARG APK_REPOSITORY=https://apk.cgr.dev/chainguard
ARG WOLFI_REPO_DIGEST=f0031424cf46f7db780ce63a45f0fd6aa6f85f601e6bb3b7a91fe3d4d5b7d2cc
ARG APK_DOWNLOAD_IMAGE=cgr.dev/chainguard/python:latest-dev@sha256:630df1be3733f7b38d1b535872904248adfe23fbea4befcb08da47cb7436ddb2

FROM ${NODE_IMAGE} AS fe

ARG NPM_VERSION

USER root

WORKDIR /builder

RUN npm install --global "npm@${NPM_VERSION}" \
    && hash -r \
    && test "$(npm --version)" = "${NPM_VERSION}"

# Install dependencies (cached)
COPY package*.json ./
RUN npm_config_maxsockets=4 npm ci --legacy-peer-deps --ignore-scripts --no-audit --no-fund --prefer-offline

# Copy ONLY required files (avoid cache busting)
COPY angular.json ./
COPY tsconfig*.json ./
COPY proxy.conf.js ./
COPY src ./src

# Relative assets let one image run at / or a runtime-configured path prefix.
RUN npm test -- --watch=false && npx ng build --base-href=./


############################################
# 2) Backend build (Rust - production optimized)
############################################
FROM ${RUST_IMAGE} AS rust-base
ARG WOLFI_REPO_DIGEST
USER root
COPY wolfi-signing.rsa.pub /tmp/wolfi-signing.rsa.pub
RUN echo "${WOLFI_REPO_DIGEST}  /tmp/wolfi-signing.rsa.pub" | sha256sum -c - \
    && mv /tmp/wolfi-signing.rsa.pub /etc/apk/keys/wolfi-signing.rsa.pub

# Build-only downloads use GNU wget; APK verifies the signed transaction offline.
FROM ${APK_DOWNLOAD_IMAGE} AS backend-packages
ARG APK_REPOSITORY
USER root
COPY --from=rust-base /usr/lib/apk/db/installed /tmp/apk-root/usr/lib/apk/db/installed
COPY --from=rust-base /etc/apk/world /tmp/apk-root/etc/apk/world
COPY --from=rust-base /etc/apk/keys/ /etc/apk/keys/
COPY container/prepare-apk-repository.sh /usr/local/bin/prepare-apk-repository.sh
RUN --mount=type=cache,id=gitlab-dashboard-release-apks,target=/tmp/apks,sharing=locked \
    sh /usr/local/bin/prepare-apk-repository.sh "$APK_REPOSITORY" /tmp/apk-root build-base cmake perl pkgconf linux-headers

FROM rust-base AS be
ARG APK_REPOSITORY
ARG CARGO_BUILD_JOBS=2
WORKDIR /builder
RUN --mount=type=bind,from=backend-packages,source=/runtime-repository,target=/runtime-repository \
    printf '%s\n' /runtime-repository > /etc/apk/repositories \
    && apk --no-network --no-progress add --no-cache $(cat /runtime-repository/constraints) \
    && printf '%s\n' "$APK_REPOSITORY" > /etc/apk/repositories

# -------------------------------
# Step 1: Cache dependencies
# -------------------------------
COPY api/Cargo.toml api/Cargo.lock ./api/
WORKDIR /builder/api

# Dummy source for dependency caching
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

# Build dependencies (cached layer)
RUN cargo build --release --locked

# -------------------------------
# Step 2: Copy real source
# -------------------------------
COPY api/src ./src

# Touch source to invalidate cache and rebuild with real code
RUN touch src/main.rs \
    && cargo test --release --locked \
    && cargo build --release --locked \
    && cp target/release/gcd_api /builder/gcd_api

# Validate binary exists (fail fast)
RUN test -f /builder/gcd_api


############################################
# 3) Certs + timezone
############################################
# The pinned static base includes the complete CA/timezone assets without APK downloads.
FROM cgr.dev/chainguard/static:latest@sha256:fe55470f22d3259488d9d3739168d8f04da67755f0b69382bc26eda4a7d3d327 AS certs


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM cgr.dev/chainguard/glibc-dynamic:latest@sha256:2a3f1ec8a825dfbb1211b5835a9b8b3fb8d76c7bd22a189b1f84157ed2028293

WORKDIR /app

# Metadata
ARG VERSION_ARG=2.14.1
ENV VERSION=${VERSION_ARG}
ENV RUST_LOG=info

# Copy certs + timezone
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=certs /usr/share/zoneinfo /usr/share/zoneinfo

# Copy frontend (non-root ownership)
COPY --chown=65532:65532 --from=fe /builder/dist/gitlab-ci-dashboard/browser ./spa

# Copy backend binary
COPY --chown=65532:65532 --from=be /builder/gcd_api ./gcd_api

EXPOSE 8080

# OpenShift runs random UID → distroless nonroot works
USER 65532:65532

ENTRYPOINT ["/app/gcd_api"]
