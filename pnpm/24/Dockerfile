# =============================================================================
# PNPM CI/CD BASE IMAGE — Node 24 LTS
# =============================================================================
# Pre-baked CI image with pnpm and common frontend tooling.
#
# Components:
#   node 24 LTS                — from official node image
#   pnpm 11                    — via npm global install
#   eslint                     — linter (pnpm global)
#   prettier                   — code formatter (pnpm global)
#   vitest                     — test runner (pnpm global)
# =============================================================================

FROM mirror.gcr.io/library/node:24-trixie-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Node 24 + pnpm 11 CI base image (eslint, prettier, vitest)" \
      org.opencontainers.image.licenses="MIT"

# Install OS packages needed for CI (SSH clone, git operations)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends openssh-client git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Pin pnpm to an explicit latest stable version for deterministic builds.
ENV PNPM_VERSION="11.21.0"
ENV PNPM_HOME="/usr/local/share/pnpm"
# pnpm 11 places global binaries in $PNPM_HOME/bin and refuses to install
# unless that directory is on PATH; pnpm 10 used $PNPM_HOME itself. Both are
# listed so the image works either way.
ENV PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"
RUN npm install -g "pnpm@${PNPM_VERSION}"

# Pinned for the same reason pnpm is: an unpinned `pnpm add -g` makes every
# rebuild a different image, which is the opposite of what the pin above is for.
# All three require Node >= 24, which this base supplies.
ENV ESLINT_VERSION="10.8.1"
ENV PRETTIER_VERSION="3.9.6"
ENV VITEST_VERSION="4.1.10"

# Install global dev tools
RUN pnpm add -g \
    "eslint@${ESLINT_VERSION}" \
    "prettier@${PRETTIER_VERSION}" \
    "vitest@${VITEST_VERSION}" && \
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
