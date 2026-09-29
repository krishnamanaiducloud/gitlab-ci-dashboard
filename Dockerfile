############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=cgr.dev/chainguard/node:latest-dev@sha256:446b1779a5c4b3d5aca6b05d77b5d7a643eef87b34ec6ba5dc55fd0c9f81a6aa
ARG RUST_IMAGE=cgr.dev/chainguard/rust:latest-dev@sha256:9bfa04d59a67a0df54c8031ab8469ed8c66b454d3b5d9f675722b75231a86c7b
ARG NPM_VERSION=12.1.0
ARG APK_REPOSITORY=https://packages.wolfi.dev/os
ARG WOLFI_REPO_DIGEST=f0031424cf46f7db780ce63a45f0fd6aa6f85f601e6bb3b7a91fe3d4d5b7d2cc

FROM ${NODE_IMAGE} AS fe

ARG NPM_VERSION

USER root

WORKDIR /builder

RUN npm install --global "npm@${NPM_VERSION}" \
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
RUN npx ng build --base-href=./


############################################
# 2) Backend build (Rust - production optimized)
############################################
FROM ${RUST_IMAGE} AS be
ARG APK_REPOSITORY
ARG WOLFI_REPO_DIGEST

USER root

WORKDIR /builder

# Install build dependencies
COPY wolfi-signing.rsa.pub /tmp/wolfi-signing.rsa.pub
RUN echo "${WOLFI_REPO_DIGEST}  /tmp/wolfi-signing.rsa.pub" | sha256sum -c - \
    && mv /tmp/wolfi-signing.rsa.pub /etc/apk/keys/wolfi-signing.rsa.pub \
    && printf '%s\n' "${APK_REPOSITORY}" > /etc/apk/repositories \
    && apk add --no-cache \
    build-base \
    cmake \
    perl \
    pkgconf \
    linux-headers

# -------------------------------
# Step 1: Cache dependencies
# -------------------------------
COPY api/Cargo.toml api/Cargo.lock ./api/
WORKDIR /builder/api

# Dummy source for dependency caching
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

# Build dependencies (cached layer)
RUN cargo build --release

# -------------------------------
# Step 2: Copy real source
# -------------------------------
COPY api/src ./src

# Touch source to invalidate cache and rebuild with real code
RUN touch src/main.rs \
    && cargo build --release \
    && cp target/release/gcd_api /builder/gcd_api

# Validate binary exists (fail fast)
RUN test -f /builder/gcd_api


############################################
# 3) Certs + timezone
############################################
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:bef0f4d47edc72a93d1537eae54eb53db2b2cc352c028128ff0f16c5b5a3c1e4 AS certs
ARG APK_REPOSITORY

USER root

RUN printf '%s\n' "${APK_REPOSITORY}" > /etc/apk/repositories \
    && apk upgrade --no-cache \
    && apk add --no-cache ca-certificates-bundle tzdata


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM cgr.dev/chainguard/glibc-dynamic:latest@sha256:6acf5a19a988abdaf0f3d30247561431a206034e702871442bed66a2c68cc1a2

WORKDIR /app

# Metadata
ARG VERSION_ARG=2.14.0
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
