# Bun CI image with the browser and tooling used by gpu-ai's quality lane.
FROM mirror.gcr.io/node:24-bookworm-slim AS node

FROM mirror.gcr.io/oven/bun:1.4.2-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Bun 1.4 CI image with Playwright Chromium and oxlint" \
      org.opencontainers.image.licenses="MIT"

USER root

# Playwright's browser driver requires Node even when the project scripts use Bun.
COPY --from=node /usr/local/bin/node /usr/local/bin/node

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    git openssh-client curl make ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Keep this Playwright version identical to gpu-ai's @playwright/test pin.
# Browser revisions change between releases; mismatched versions ignore the baked browsers.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN mkdir -p /opt/ci-tools && \
    cd /opt/ci-tools && \
    bun add oxlint@1.82.0 playwright@1.63.0 && \
    ln -s /opt/ci-tools/node_modules/.bin/oxlint /usr/local/bin/oxlint && \
    ln -s /opt/ci-tools/node_modules/.bin/playwright /usr/local/bin/playwright && \
    playwright install --with-deps chromium && \
    chmod -R a+rX "$PLAYWRIGHT_BROWSERS_PATH" && \
    bun --version && node --version && oxlint --version && playwright --version

WORKDIR /app
RUN chown bun:bun /app
USER bun
