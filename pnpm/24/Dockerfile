# =============================================================================
# PNPM CI/CD BASE IMAGE — Node 24 LTS
# =============================================================================
# Pre-baked CI image with pnpm and common frontend tooling.
# Legacy: kept for consumers not yet migrated to bun (see bun/1).
#
# Components:
#   node 24 LTS                — from official node image
#   pnpm 10                    — via npm global install
#   eslint                     — linter (pnpm global)
#   prettier                   — code formatter (pnpm global)
#   vitest                     — test runner (pnpm global)
# =============================================================================

FROM mirror.gcr.io/library/node:24-trixie-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Node 24 + pnpm 10 CI base image (eslint, prettier, vitest) — legacy, prefer bun:1" \
      org.opencontainers.image.licenses="MIT"

# Install OS packages needed for CI (SSH clone, git operations)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends openssh-client git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Pin pnpm to an explicit latest stable version for deterministic builds.
ENV PNPM_VERSION="10.34.5"
ENV PNPM_HOME="/usr/local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN npm install -g "pnpm@${PNPM_VERSION}"

# Install global dev tools
RUN pnpm add -g \
    eslint \
    prettier \
    vitest && \
    pnpm store prune

# Verify all components
RUN node --version && \
    pnpm --version && \
    eslint --version && \
    prettier --version

# Set working directory
WORKDIR /app

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app
