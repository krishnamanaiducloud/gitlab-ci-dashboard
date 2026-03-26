############################################
# 1) Frontend build
############################################
FROM node:25.8.1-alpine3.23 AS fe

WORKDIR /builder

COPY package*.json ./
RUN npm ci --legacy-peer-deps --ignore-scripts

COPY angular.json ./
COPY tsconfig*.json ./
COPY proxy.conf.js ./
COPY .npmrc ./
COPY src ./src

RUN npm run build


############################################
# 2) Backend build (Rust FIXED)
############################################
FROM rust:alpine3.23 AS be

WORKDIR /builder

RUN apk add --no-cache \
    build-base \
    pkgconfig \
    openssl-dev \
    openssl-libs-static

# Copy dependency files first
COPY api/Cargo.toml api/Cargo.lock ./api/

WORKDIR /builder/api

# Create dummy app for caching
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

RUN cargo build --release

# Copy real source
COPY api/src ./src

# Force clean + rebuild (fix missing binary issue)
RUN cargo clean && cargo build --release

# Validate binary exists (fail fast if not)
RUN test -f target/release/gcd_api


############################################
# 3) Certs
############################################
FROM alpine:3.23.3 AS certs
RUN apk add --no-cache ca-certificates tzdata


############################################
# 4) Runtime
############################################
FROM gcr.io/distroless/static:nonroot

WORKDIR /app

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=certs /usr/share/zoneinfo /usr/share/zoneinfo

COPY --from=fe /builder/dist/gitlab-ci-dashboard/browser ./spa

# Now this will WORK
COPY --from=be /builder/api/target/release/gcd_api ./gcd_api

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/app/gcd_api"]
