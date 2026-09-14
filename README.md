# platform-images

[![Build & Publish](https://github.com/e2enetworks-oss/platform-images/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/e2enetworks-oss/platform-images/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%C2%B7%20linux%2Farm64-lightgrey.svg)](#consume-an-image)

[![rust](https://img.shields.io/badge/rust-1.98.1-orange.svg)](#consume-an-image)
[![bun](https://img.shields.io/badge/bun-1.4.2-black.svg)](#consume-an-image)
[![python](https://img.shields.io/badge/python-3.11%20%C2%B7%203.12%20%C2%B7%203.14-blue.svg)](#consume-an-image)
[![node](https://img.shields.io/badge/node-24-green.svg)](#consume-an-image)

CI base images for E2E Networks, published to GitHub Container Registry (GHCR).
Every image supports `linux/amd64` and `linux/arm64`.

## Consume an image

**Use the immutable `<sha7>` tag in production (`image:` in CI, `FROM` in a Dockerfile); use the moving `latest` tag for local development only.**

```dockerfile
FROM ghcr.io/e2enetworks-oss/rust:1.98.1-a1b2c3d
```

| Image | Immutable tag — use this | Moving tag — local dev only | Includes |
|---|---|---|---|
| `ghcr.io/e2enetworks-oss/python` | `python:3.11-<sha7>` | `python:3.11-latest` | Python, uv, pipenv, Ansible, Ruff, Pyright, Semgrep, pytest |
| `ghcr.io/e2enetworks-oss/python` | `python:3.12-<sha7>` | `python:3.12-latest` | Python 3.12, Python CI tools, native build headers, and an e2e-gpu compatibility wheelhouse |
| `ghcr.io/e2enetworks-oss/python` | `python:3.14-<sha7>` | `python:3.14-latest` | Python 3.14 and the Python CI tools |
| `ghcr.io/e2enetworks-oss/rust` | `rust:1.98.1-<sha7>` | `rust:latest` | Rust, cargo-chef, grcov, sccache, cargo-audit, protobuf |
| `ghcr.io/e2enetworks-oss/helm-vector` | `helm-vector:<sha7>` | `helm-vector:latest` | Helm, Vector, Bash, curl, OpenSSL |
| `ghcr.io/e2enetworks-oss/pnpm` | `pnpm:24-<sha7>` | `pnpm:24-latest` | Node 24, pnpm 11, ESLint, Prettier, Vitest |
| `ghcr.io/e2enetworks-oss/bun` | `bun:1.4-<sha7>` | `bun:1.4-latest` | Bun 1.4, Git, SSH, curl, Make |
| `ghcr.io/e2enetworks-oss/bun-playwright` | `bun-playwright:1.4-<sha7>` | `bun-playwright:1.4-latest` | Bun 1.4.2, Playwright 1.63.0 with Chromium, oxlint 1.82.0, Git, SSH, curl, Make, and Node for Playwright's driver |

`<sha7>` is the seven-character hash of the publishing commit — find it with
`make list` or in the merge job's summary. Rust takes its tag prefix from
`rust/VERSION`; every other image takes it from its directory name.

The images are public, so pulls need no token.

### Python 3.12 e2e-gpu wheelhouse

The Python 3.12 image contains architecture-native compatibility wheels in
`/opt/wheels` for e2e-gpu pins that otherwise compile during dependency
installation. Use the wheelhouse as an extra package source while retaining the
normal package index for all other dependencies:

```sh
uv pip install --find-links=/opt/wheels -r requirements.txt
```

The wheelhouse is built and smoke-tested independently on `linux/amd64` and
`linux/arm64`. Its exact direct pins are recorded in
`/opt/wheels/requirements.txt` inside the image.

The `django-safedelete==0.3.2` wheel carries a narrow Django 4.2 import patch.
It intentionally preserves the package's Boolean `deleted` field and legacy
`safedelete_mixin_factory` API used by e2e-gpu.

## CI

- Pull requests build changed images for both architectures without publishing.
- Merging to `main` builds and pushes the changed images to GHCR.
- Manual runs can rebuild all images or a comma-separated list.
- Gitleaks scans the repository before any build.
- Trivy scans every built image on both architectures. It reports all Critical CVEs and fails the workflow when a fix is available.

The build uses native runners, so it does not use QEMU emulation.

## How to publish an image

Build and smoke-test one image locally (current architecture), and run the
repository checks:

```sh
make build IMAGE=bun/1.4    # build one image for the current architecture
make test IMAGE=bun/1.4     # run its smoke test
make lint                   # lint Dockerfiles, workflows, and shell
make test-unit              # run unit tests
```

Build and push an image for both architectures (manual pushes need a GitHub
token with `write:packages`):

```sh
gh auth login
make push IMAGE=bun/1.4
```

Rebuild and publish without a code change:

```sh
gh workflow run build.yml -f images=all
gh workflow run build.yml -f images=rust,bun/1.4
```

### Add an image

1. Create `<name>/Dockerfile` or `<name>/<version>/Dockerfile`.
2. Add the directory to `IMAGES` in `make/build.mk`.
3. Add its smoke test to the `test` target.
4. Add it to the table above.
5. Open a pull request — merging to `main` builds and publishes it.

`IMAGES` is the single source of truth for CI path filters and build matrices.
