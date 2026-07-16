############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=node:24.18.0-alpine3.24@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd
ARG RUST_IMAGE=rust:1.96.1-alpine3.24@sha256:a41f7740f8b45d45795624eec13a8b42263cc700f19f7e4e86e04d3dda08a479

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

# Relative assets let one image run at / or a runtime-configured path prefix.
RUN npx ng build --base-href=./


############################################
# 2) Backend build (Rust - production optimized)
############################################
FROM ${RUST_IMAGE} AS be

WORKDIR /builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    cmake \
    perl \
    pkgconfig \
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
RUN touch src/main.rs && cargo build --release

# Validate binary exists (fail fast)
RUN test -f target/release/gcd_api


############################################
# 3) Certs + timezone
############################################
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS certs

RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates tzdata \
    && update-ca-certificates


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM gcr.io/distroless/static-debian13:nonroot@sha256:f7f8f729987ad0fdf6b05eeeae94b26e6a0f613bdf46feea7fc40f7bd72953e6

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
