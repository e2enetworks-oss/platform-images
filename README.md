# platform-images

CI base images for E2E Networks, published to GitHub Container Registry (GHCR).
Every image supports `linux/amd64` and `linux/arm64`.

## Images

| Directory | Image | Includes |
|---|---|---|
| `python/3.11` | `ghcr.io/e2enetworks-oss/python:3.11-*` | Python, uv, pipenv, Ansible, Ruff, Pyright, Semgrep, pytest |
| `python/3.12` | `ghcr.io/e2enetworks-oss/python:3.12-*` | Python 3.12, Python CI tools, and native build headers including libffi |
| `python/3.14` | `ghcr.io/e2enetworks-oss/python:3.14-*` | Python 3.14 and the Python CI tools |
| `rust` | `ghcr.io/e2enetworks-oss/rust:*` | Rust, cargo-chef, grcov, sccache, cargo-audit, protobuf |
| `helm-vector` | `ghcr.io/e2enetworks-oss/helm-vector:*` | Helm, Vector, Bash, curl, OpenSSL |
| `pnpm/24` | `ghcr.io/e2enetworks-oss/pnpm:24-*` | Node 24, pnpm 11, ESLint, Prettier, Vitest |
| `bun/1.4` | `ghcr.io/e2enetworks-oss/bun:1.4-*` | Bun 1.4, Git, SSH, curl, Make |

## Image tags

Use immutable tags in production. Use `latest` for local development only.

| Image | Immutable tag | Moving tag |
|---|---|---|
| Rust | `rust:1.98.0-a1b2c3d` | `rust:latest` |
| Versioned image | `python:3.14-a1b2c3d` | `python:3.14-latest` |
| Bare image | `helm-vector:a1b2c3d` | `helm-vector:latest` |

Rust reads its version from `rust/VERSION`.

## CI

- Pull requests build changed images for both architectures without publishing.
- Merging to `main` builds and pushes the changed images to GHCR.
- Manual runs can rebuild all images or a comma-separated list.
- Gitleaks scans the repository before any build.
- Trivy scans every built image on both architectures. It reports all Critical CVEs and fails the workflow when a fix is available.

The build uses native runners, so it does not use QEMU emulation.

To rebuild without a code change:

```sh
gh workflow run build.yml -f images=all
gh workflow run build.yml -f images=rust,bun/1.4
```

## Local development

```sh
make build IMAGE=bun/1.4    # build one image for the current architecture
make test IMAGE=bun/1.4     # run its smoke test
make lint                   # lint Dockerfiles, workflows, and shell
make test-unit              # run unit tests
```

Build and push an image for both architectures:

```sh
gh auth login
make push IMAGE=bun/1.4
```

## Consume an image

```dockerfile
FROM ghcr.io/e2enetworks-oss/rust:1.98.0-a1b2c3d
```

The images are public. Manual pushes need a GitHub token with `write:packages`.

## Add an image

1. Create `<name>/Dockerfile` or `<name>/<version>/Dockerfile`.
2. Add the directory to `IMAGES` in `make/build.mk`.
3. Add its smoke test to the `test` target.
4. Add it to the table above.
5. Open a pull request.

`IMAGES` is the single source of truth for CI path filters and build matrices.
