# =============================================================================
# BUN CI/CD BASE IMAGE — Bun 1.4
# =============================================================================
# Pre-baked CI image for Bun/TypeScript services. Pinned to the 1.4 minor, the
# way python/3.11 and python/3.14 are: consumers reproduce a build by pinning an
# immutable tag, and a floating base defeats that from underneath them.
# Debian-slim base rather than alpine: esbuild/sharp native modules assume
# glibc — musl compatibility is not worth the size saving.
#
# Components:
#   bun 1.4                    — from official oven/bun image
#   git, openssh-client        — CI clone operations
#   curl, ca-certificates      — fetching + TLS
# =============================================================================

FROM mirror.gcr.io/oven/bun:1.4-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Bun 1.4 CI base image (git, ssh, curl)" \
      org.opencontainers.image.licenses="MIT"

USER root

# Install OS packages needed for CI (SSH clone, git operations)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    curl \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# oven/bun ships a non-root "bun" user — use it
RUN mkdir -p /app && chown -R bun:bun /app
USER bun

# Verify all components
RUN bun --version && \
    git --version && \
    curl --version
