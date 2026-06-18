############################################
# 1) Frontend build
############################################
FROM node:24.16-alpine3.23 AS fe

WORKDIR /builder

COPY package*.json ./
RUN npm ci --legacy-peer-deps --ignore-scripts

COPY angular.json ./
COPY tsconfig*.json ./
COPY proxy.conf.js ./
COPY src ./src

ARG BASE_PATH=/
RUN npx ng build --base-href=${BASE_PATH}


############################################
# 2) Backend build (Rust FIXED)
############################################
FROM rust:1.96.0-alpine3.23 AS be

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

# Touch source to invalidate cache and rebuild with real code
RUN touch src/main.rs && cargo build --release

# Validate binary exists (fail fast if not)
RUN test -f target/release/gcd_api


############################################
# 3) Certs
############################################
FROM alpine:3.24.1 AS certs
RUN apk update && apk upgrade --no-cache \
    && apk add --no-cache ca-certificates tzdata


############################################
# 4) Runtime
############################################
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=certs /usr/share/zoneinfo /usr/share/zoneinfo

COPY --from=fe /builder/dist/gitlab-ci-dashboard/browser ./spa

# Now this will WORK
COPY --from=be /builder/api/target/release/gcd_api ./gcd_api

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/app/gcd_api"]