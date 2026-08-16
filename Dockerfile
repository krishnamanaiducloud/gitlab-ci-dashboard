############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=cgr.dev/chainguard/node:latest-dev@sha256:39708a466eb9e1c4a49abc6931dc8aaf8d3d4565fe6977a53bff0ce1c357a405
ARG RUST_IMAGE=cgr.dev/chainguard/rust:latest-dev@sha256:04ff740c14814353701c10bec4e79bac5d94f10c3e54369e2688bfaf54662092

FROM ${NODE_IMAGE} AS fe

USER root

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
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:0a8fd427de5882aed77471b0a432c3675eda6b6a0ae952b5d640b46da628cdbe AS certs

RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates-bundle tzdata


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM cgr.dev/chainguard/glibc-dynamic:latest@sha256:df4e22a4b5dcd8e15a51fe9b04e16717d411dd9f4fe4b3844c1bf425b14be303

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
