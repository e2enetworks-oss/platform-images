# =============================================================================
# BUN CI/CD BASE IMAGE — Bun 1.x
# =============================================================================
# Pre-baked CI image for Bun/TypeScript services. Track 1.x latest
# (oven/bun:1-slim always resolves to the latest 1.x).
# Debian-slim base rather than alpine: esbuild/sharp native modules assume
# glibc — musl compatibility is not worth the size saving.
#
# Components:
#   bun 1.x                    — from official oven/bun image
#   git, openssh-client        — CI clone operations
#   curl, ca-certificates      — fetching + TLS
# =============================================================================

FROM mirror.gcr.io/oven/bun:1-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Bun 1.x CI base image (git, ssh, curl)" \
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
