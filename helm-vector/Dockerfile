# =============================================================================
# HELM-VECTOR CI BASE IMAGE — helm + vector
# =============================================================================
# Pre-baked CI image for infra validation jobs.
# Eliminates per-run installation of helm and vector.
#
# Components:
#   helm      — Kubernetes chart linting and templating
#   vector    — config validation for Vector pipeline configs
#   bash, grep, curl, openssl  — shell tooling required by validation scripts
#
# Multi-arch: the vector tarball is selected per buildx TARGETARCH
# (amd64 → x86_64, arm64 → aarch64).
# =============================================================================

ARG HELM_VERSION=4.2.3
ARG VECTOR_VERSION=0.57.0

FROM mirror.gcr.io/alpine/helm:${HELM_VERSION}

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Infra CI base image (helm, vector, shell tooling)" \
      org.opencontainers.image.licenses="MIT"

ARG VECTOR_VERSION
# sha256 of the vector release tarball per architecture.
# Regenerate on a version bump: curl -fsSL <url> | sha256sum
ARG VECTOR_SHA256_AMD64=b04fafcffcbeb3d43cbba587583dbe3338b24dd34256b3967fb15d137aff75f2
ARG VECTOR_SHA256_ARM64=81cec5343e49985351e13f76ae3d550d7b0f0ac64fd4d88c07e3873bdfdf100a
ARG TARGETARCH

# busybox ash needs -e and pipefail spelled out, or the checksum comparison
# below would fail silently inside its pipeline.
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache bash grep curl openssl ca-certificates \
    && case "${TARGETARCH}" in \
         amd64) VECTOR_ARCH="x86_64";  VECTOR_SHA256="${VECTOR_SHA256_AMD64}" ;; \
         arm64) VECTOR_ARCH="aarch64"; VECTOR_SHA256="${VECTOR_SHA256_ARM64}" ;; \
         *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/vector.tar.gz \
       "https://github.com/vectordotdev/vector/releases/download/v${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${VECTOR_ARCH}-unknown-linux-musl.tar.gz" \
    && echo "${VECTOR_SHA256}  /tmp/vector.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/vector.tar.gz -C /tmp \
    && mv "/tmp/vector-${VECTOR_ARCH}-unknown-linux-musl/bin/vector" /usr/local/bin/vector \
    && rm -rf /tmp/vector.tar.gz /tmp/vector-* \
    && helm version \
    && vector --version

# alpine/helm sets ENTRYPOINT ["helm"] — reset so CI runners can exec shell scripts
ENTRYPOINT []
CMD ["/bin/sh"]
