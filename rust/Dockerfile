# =============================================================================
# RUST CI/CD BASE IMAGE — rust:${RUST_VERSION}
# =============================================================================
# Pre-baked CI image with all tooling installed.
#
# The four cargo tools are fetched as upstream prebuilt binaries via
# cargo-binstall rather than compiled from source. Compiling them costs 20-40
# minutes per architecture (hours under QEMU emulation); fetching the artifacts
# the upstream projects already publish and test costs seconds. Every version
# is pinned, and `--disable-strategies compile` makes an unresolvable binary a
# loud build failure instead of a silent fallback to a source build.
#
# Components:
#   rustc, cargo, rustfmt, clippy          — from official rust image
#   cargo-chef                             — dependency caching for Docker builds
#   grcov                                  — LLVM profile coverage reporter
#   cargo-audit                            — dependency vulnerability scanner
#   sccache                                — shared compilation cache
#   protobuf-compiler                      — for gRPC/tonic builds
#
# Build with specific versions:
#   docker buildx build --build-arg RUST_VERSION=1.97.1 ...
# =============================================================================

ARG RUST_VERSION=1.97.1

# ---------------------------------------------------------------------------
# Tool fetch stage — keeps cargo-binstall and its metadata out of the final image
# ---------------------------------------------------------------------------
FROM mirror.gcr.io/library/rust:${RUST_VERSION}-slim-trixie AS toolbuilder

ARG BINSTALL_VERSION=1.21.1
ARG CARGO_CHEF_VERSION=0.1.78
ARG GRCOV_VERSION=0.10.7
ARG SCCACHE_VERSION=0.17.0
ARG CARGO_AUDIT_VERSION=0.22.2
# sha256 of cargo-audit-<target>-v<version>.tgz as published by rustsec.
# Regenerate on a version bump: curl -fsSL <url> | sha256sum
ARG CARGO_AUDIT_SHA256_AMD64=ab28a1bdb54db4d5d8ad5981cf1f959410370b3d28250dbd35f6a44248620e39
ARG CARGO_AUDIT_SHA256_ARM64=c6603814ddaa45e51263dafd31c0ac98808f688d26f7395804f9670b0fd599dd
ARG TARGETARCH

# curl | tar below — fail the build if curl fails rather than feeding tar nothing
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# cargo-chef, grcov and sccache: prebuilt binaries from each project's own
# GitHub releases. `quick-install` is disabled alongside `compile` so binstall
# cannot quietly substitute a third-party rebuild for the upstream artifact.
RUN case "${TARGETARCH}" in \
      amd64) TOOL_ARCH="x86_64" ;; \
      arm64) TOOL_ARCH="aarch64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/cargo-bins/cargo-binstall/releases/download/v${BINSTALL_VERSION}/cargo-binstall-${TOOL_ARCH}-unknown-linux-musl.tgz" \
       | tar -xz -C /usr/local/cargo/bin cargo-binstall \
    && mkdir -p /out \
    && cargo binstall --no-confirm --no-track --disable-strategies compile,quick-install \
       --install-path /out \
       "cargo-chef@${CARGO_CHEF_VERSION}" \
       "grcov@${GRCOV_VERSION}" \
       "sccache@${SCCACHE_VERSION}"

# cargo-audit separately: binstall cannot resolve rustsec's asset naming from
# GitHub, and letting it fall through to quick-install would source the security
# scanner from a third-party rebuild. Pinned URL + checksum instead.
RUN case "${TARGETARCH}" in \
      amd64) CA_TARGET="x86_64-unknown-linux-gnu";  CA_SHA256="${CARGO_AUDIT_SHA256_AMD64}" ;; \
      arm64) CA_TARGET="aarch64-unknown-linux-gnu"; CA_SHA256="${CARGO_AUDIT_SHA256_ARM64}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && CA_DIR="cargo-audit-${CA_TARGET}-v${CARGO_AUDIT_VERSION}" \
    && curl -fsSL -o /tmp/cargo-audit.tgz \
       "https://github.com/rustsec/rustsec/releases/download/cargo-audit%2Fv${CARGO_AUDIT_VERSION}/${CA_DIR}.tgz" \
    && echo "${CA_SHA256}  /tmp/cargo-audit.tgz" | sha256sum -c - \
    && tar -xzf /tmp/cargo-audit.tgz -C /out --strip-components=1 "${CA_DIR}/cargo-audit" \
    && rm /tmp/cargo-audit.tgz

# ---------------------------------------------------------------------------
# Final image
# ---------------------------------------------------------------------------
FROM mirror.gcr.io/library/rust:${RUST_VERSION}-slim-trixie

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Rust CI base image (cargo-chef, grcov, sccache, cargo-audit, protobuf)" \
      org.opencontainers.image.licenses="MIT"

# Install system dependencies needed by common Rust projects
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    git \
    curl \
    pkg-config \
    build-essential \
    libssl-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Ensure rustfmt + clippy are installed, then remove source/docs (~200MB saving).
RUN rustup component add rustfmt clippy llvm-tools && \
    rm -rf /usr/local/rustup/toolchains/*/lib/rustlib/src \
           /usr/local/rustup/toolchains/*/lib/rustlib/rustc-src \
           /usr/local/rustup/toolchains/*/share/doc \
           /usr/local/rustup/toolchains/*/share/man

COPY --from=toolbuilder /out/ /usr/local/cargo/bin/

# ---------------------------------------------------------------------------
# Verify all components
# ---------------------------------------------------------------------------
RUN rustc --version && \
    cargo --version && \
    rustfmt --version && \
    cargo clippy --version && \
    cargo-audit --version && \
    cargo chef --version && \
    grcov --version && \
    sccache --version && \
    protoc --version

# Set working directory
WORKDIR /app

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash app \
    && mkdir -p /tmp/sccache \
    && chown -R app:app /app /tmp/sccache
USER app

# Default sccache config (CI can override via env vars)
ENV RUSTC_WRAPPER=sccache
ENV SCCACHE_DIR=/tmp/sccache
