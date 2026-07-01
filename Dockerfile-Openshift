############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=node:24.18.0-alpine3.24
ARG RUST_IMAGE=rust:1.96.1-alpine3.24

FROM ${NODE_IMAGE} AS fe

WORKDIR /builder

# Install dependencies (cached)
COPY package*.json ./
RUN npm ci --legacy-peer-deps --ignore-scripts

# Copy ONLY required files (avoid cache busting)
COPY angular.json ./
COPY tsconfig*.json ./
COPY proxy.conf.js ./
COPY src ./src

# Build Angular (BASE_PATH for Istio VirtualService path-based routing)
ARG BASE_PATH=/
RUN npx ng build --base-href=${BASE_PATH}


############################################
# 2) Backend build (Rust - production optimized)
############################################
FROM ${RUST_IMAGE} AS be

WORKDIR /builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    pkgconfig \
    openssl-dev \
    openssl-libs-static

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
RUN touch src/main.rs && cargo build --release

# Validate binary exists (fail fast)
RUN test -f target/release/gcd_api


############################################
# 3) Certs + timezone
############################################
FROM alpine:3.24.1 AS certs

RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates tzdata \
    && update-ca-certificates


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM gcr.io/distroless/static-debian12:nonroot

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
COPY --chown=65532:65532 --from=be /builder/api/target/release/gcd_api ./gcd_api

EXPOSE 8080

# OpenShift runs random UID → distroless nonroot works
USER 65532:65532

ENTRYPOINT ["/app/gcd_api"]
