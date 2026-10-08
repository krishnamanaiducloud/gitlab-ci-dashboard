# v15 / application 2.14.1

## Changes

- Refresh digest-pinned Chainguard Node, Rust, Wolfi and glibc-dynamic bases.
- Runtime base `cgr.dev/chainguard/glibc-dynamic:latest@sha256:2a3f1ec8a825dfbb1211b5835a9b8b3fb8d76c7bd22a189b1f84157ed2028293` was inspected and contains Wolfi glibc 2.44-r8.
- The debug build also verifies that its installed Wolfi glibc package is at least 2.44-r8.
- Install build/debug APK dependencies offline from a signed repository transaction, with HTTPS downloads isolated to a build-only GNU-wget stage. A digest-pinned Chainguard static stage provides the certificate/timezone assets; there is no blanket APK upgrade or download tooling in the production runtime.
- Update the frontend build's pinned npm tool to 12.2.0.
- Update Angular build/CLI to 22.2.2, Node type definitions to 26.6.4, jsdom to 30.1.2 and Tokio to 1.53.2, with lockfiles.
- Align frontend, Rust package and runtime application metadata to version 2.14.1.
- Pin build-only source-map-js 1.2.2 to remediate its indexed-source-map denial-of-service advisory.
- Retain Angular runtime 22.2.1 and TypeScript 6.0.3: the former is the latest stable runtime and requires TypeScript >=6.0 and <6.1. TypeScript 7 is not compatible.
- Run frontend and backend unit tests in the production image build. Cargo builds and tests use the committed lockfile and release profile, avoiding a duplicate full debug-profile dependency compilation while testing production compilation settings.
- Refresh CI toolchains to stable Node 26.11.1 and Rust 1.99.0. Branch pushes retain validation but no longer publish branch-name images; release publishing accepts only stable numeric version tags and never adds `latest`.
- Preserve the shell-free non-root production runtime, debug separation, certificate validation and application API behavior.
- Replace startup logging of the full application configuration with a safe worker-count event: the former included the GitLab API token when debug logging was enabled. Release smoke tests reject token leakage in container logs and verify graceful non-root termination.

## Security checks and remaining issue

Official npm bulk advisory checks of the updated lockfile returned no advisory packages. OSV queried all 320 registry packages in Cargo.lock and reported one unresolved advisory:

`actix-web / actix-http 3.18.12 -> h2 0.3.27 -> RUSTSEC-2026-0258` (unbounded empty HTTP/2 DATA frames).

The latest compatible Actix HTTP dependency still selects h2 0.3.27. The patched h2 0.4 series is an incompatible API change, so replacing only the lockfile version is unsafe. The lock also contains patched h2 0.4.19 for a separate dependency chain; this does not fix the 0.3.27 copy. HTTP/2 functionality has not been disabled or silently removed. Actual exposure depends on deployment protocol/termination and requires deployment-specific review. This release must not be described as vulnerability-free.

Primary advisory: <https://rustsec.org/advisories/RUSTSEC-2026-0258.html>.

Official package metadata: <https://crates.io/api/v1/crates/actix-http/3.18.12/dependencies> and <https://crates.io/api/v1/crates/h2>.

## Publication

Only versioned tags `mohankrishna999/gitlab-ci-dashboard:v15` and `mohankrishna999/gitlab-ci-dashboard:v15-debug` are in scope. Production and debug must pass build and arbitrary-UID HTTP health checks before publication. Existing optional-chain compiler warnings are not remediated by unrelated UI refactoring.

## Executed release validation

- Production image build: 27 frontend tests and 53 Rust backend tests passed; the Angular production bundle and locked Rust release binary built successfully.
- Both images passed HTTP `/health` smoke checks as UID `1000820000`, with a read-only root filesystem, all capabilities dropped and `no-new-privileges`. Both stopped gracefully with exit code 0. A synthetic token was absent from their container logs.
- Debug APK database reports `glibc-2.44-2.44-r8` and its matching POSIX locale package. Production uses the inspected glibc-dynamic digest above.
- Published production digest: `sha256:56d3bb9d118af05c5263c8b1b38c7bc70f38d10678ddb827ab5eb92a8a5b9924`.
- Published debug digest: `sha256:7d9c52599f9d2915123f1bbc3a8b69cc3add605840c3c024d4b4786bac3fd521`.
- Docker Hub reports 13,057,928 compressed bytes for the production manifest. The debug image keeps its separate operational tools; it is not the default runtime.
- Fresh-database Trivy scans of both exact published digests returned zero image findings. The separate Cargo-source `h2 0.3.27` advisory described above remains unresolved; an image scanner's lack of Rust source inventory is not evidence that this dependency is patched.
