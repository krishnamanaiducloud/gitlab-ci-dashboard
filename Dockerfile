############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=cgr.dev/chainguard/node:latest-dev@sha256:5ce325a19f6941e2c922cb9110d3d0c6c555ca82d050bc2ef5d72254792bf243
ARG RUST_IMAGE=cgr.dev/chainguard/rust:latest-dev@sha256:635c2f1ae6306ebcbeda3857013f065be7e1ed5dff0f8aff7a6a7a1bce459cac

FROM ${NODE_IMAGE} AS fe

USER root

WORKDIR /builder

# Install dependencies (cached)
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --legacy-peer-deps --ignore-scripts --no-audit --no-fund --prefer-offline

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

USER root

WORKDIR /builder

# Install build dependencies
RUN apk add --no-cache \
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
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/builder/api/target \
    cargo build --release

# -------------------------------
# Step 2: Copy real source
# -------------------------------
COPY api/src ./src

# Touch source to invalidate cache and rebuild with real code
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/builder/api/target \
    touch src/main.rs \
    && cargo build --release \
    && cp target/release/gcd_api /builder/gcd_api

# Validate binary exists (fail fast)
RUN test -f /builder/gcd_api


############################################
# 3) Certs + timezone
############################################
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:3754b6da0e1ccdab0fe46abfdd7bbbba994b593c28149f6659fa6597f2261aeb AS certs

USER root

RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates-bundle tzdata


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM cgr.dev/chainguard/glibc-dynamic:latest@sha256:94ec8c23c45c7aad22b6ab400dc7e1b46dd36f4c71d6c7a3976c8ad4e36ca266

WORKDIR /app

# Metadata
ARG VERSION_ARG=0.0.4
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
