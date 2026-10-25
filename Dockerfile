############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=cgr.dev/chainguard/node:latest-dev@sha256:13afe2c05d49286578b74c4a14b8e4bbe70e98828abeb3d0ea9f9fd2af4cc431
ARG RUST_IMAGE=cgr.dev/chainguard/rust:latest-dev@sha256:3b50cecf04a9ef03416637dcba27a1ea1e612e4ad4ee04b96f347af60948910b
ARG NPM_VERSION=12.2.1
ARG APK_REPOSITORY=https://apk.cgr.dev/chainguard
ARG WOLFI_REPO_DIGEST=f0031424cf46f7db780ce63a45f0fd6aa6f85f601e6bb3b7a91fe3d4d5b7d2cc
ARG APK_DOWNLOAD_IMAGE=cgr.dev/chainguard/python:latest-dev@sha256:c179c7d8e23caed59a51ff74d4742f8f8d3f16af4c33c40acaf8d3ee07234592

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
FROM cgr.dev/chainguard/static:latest@sha256:c12f0107f8afb0bbc1b0eff96ff8675e85a10c6083d039b777c51fef5c27420f AS certs


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM cgr.dev/chainguard/glibc-dynamic:latest@sha256:2827063c9efb4ba971d8621eb75f4e61b8d19850a6293a797df37358cc6f687b

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
