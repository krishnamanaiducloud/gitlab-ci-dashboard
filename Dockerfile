############################################
# 1) Frontend build (Angular - optimized)
############################################
ARG NODE_IMAGE=cgr.dev/chainguard/node:latest-dev@sha256:c73a5061e27b54daadcd0175194a860986f026a40d8b7b77166e6af008ea503b
ARG RUST_IMAGE=cgr.dev/chainguard/rust:latest-dev@sha256:5df0e538ec0c335f6575681624d16c43add2223e6bd9dfdaa6f80126762b0ca8
ARG NPM_VERSION=12.0.2
ARG APK_REPOSITORY=https://apk.cgr.dev/chainguard
ARG WOLFI_REPO_DIGEST=f0031424cf46f7db780ce63a45f0fd6aa6f85f601e6bb3b7a91fe3d4d5b7d2cc

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
    && apk --timeout 60 add --no-cache \
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
FROM cgr.dev/chainguard/wolfi-base:latest@sha256:82d42999b1bc4b2aa724b442d300194901e64563efec75b3245e41f4c09fb6d2 AS certs
ARG APK_REPOSITORY

USER root

RUN printf '%s\n' "${APK_REPOSITORY}" > /etc/apk/repositories \
    && apk --timeout 60 upgrade --no-cache \
    && apk --timeout 60 add --no-cache ca-certificates-bundle tzdata


############################################
# 4) Runtime (OpenShift compliant)
############################################
FROM cgr.dev/chainguard/glibc-dynamic:latest@sha256:7bb9fa90bfaa2fc685d0df18301e5886ed171c27087602edededf1b099299e6e

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
