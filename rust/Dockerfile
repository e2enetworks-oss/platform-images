# =============================================================================
# RUST CI/CD BASE IMAGE — rust:${RUST_VERSION}
# =============================================================================
# Pre-baked CI image with all tooling installed.
# All tools compiled in toolbuilder stage and copied to final image,
# keeping compile artifacts and registry cache out of the shipped layers.
#
# Components:
#   rustc, cargo, rustfmt, clippy          — from official rust image
#   cargo-chef                             — dependency caching for Docker builds
#   grcov                                  — LLVM profile coverage reporter
#   cargo-audit                            — dependency vulnerability scanner
#   sccache                                — shared compilation cache
#   protobuf-compiler                      — for gRPC/tonic builds
#
# Build with specific version:
#   docker buildx build --build-arg RUST_VERSION=1.94.0 ...
# =============================================================================

ARG RUST_VERSION=1.94.0
FROM mirror.gcr.io/library/rust:${RUST_VERSION}-slim-trixie AS toolbuilder

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Cache mounts keep the cargo registry/git checkouts out of the image layers
# entirely while still making repeat CI builds fast.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo install cargo-chef --locked && \
    cargo install grcov --locked && \
    cargo install sccache --locked && \
    cargo install cargo-audit --locked

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

# ---------------------------------------------------------------------------
# Copy all tools from builder — compile artifacts stay out of final image.
# ---------------------------------------------------------------------------
COPY --from=toolbuilder /usr/local/cargo/bin/cargo-chef /usr/local/cargo/bin/cargo-chef
COPY --from=toolbuilder /usr/local/cargo/bin/grcov /usr/local/cargo/bin/grcov
COPY --from=toolbuilder /usr/local/cargo/bin/sccache /usr/local/cargo/bin/sccache
COPY --from=toolbuilder /usr/local/cargo/bin/cargo-audit /usr/local/cargo/bin/cargo-audit

# Strip symbols from tool binaries to reduce image size.
RUN strip /usr/local/cargo/bin/cargo-chef \
    /usr/local/cargo/bin/grcov \
    /usr/local/cargo/bin/sccache \
    /usr/local/cargo/bin/cargo-audit

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
