# platform-images

Continuous Integration (CI) base images for E2E Networks are published to GitHub Container Registry (GHCR).
Every image supports `linux/amd64` and `linux/arm64`. A build runs only when its image directory changes.
Each architecture uses a native runner. No build uses Quick Emulator (QEMU) emulation.

## Images

| Directory | Published as | Contents |
|---|---|---|
| `python/3.11` | `ghcr.io/e2enetworks-oss/python:3.11-*` | uv, pipenv, ansible, ruff, pyright, semgrep, pytest, Django stack |
| `python/3.14` | `ghcr.io/e2enetworks-oss/python:3.14-*` | same as 3.11 + libxml2/libxslt/libxmlsec headers |
| `rust` | `ghcr.io/e2enetworks-oss/rust:*` | cargo-chef, grcov, sccache, cargo-audit, protobuf |
| `helm-vector` | `ghcr.io/e2enetworks-oss/helm-vector:*` | helm, vector, bash, curl, openssl (alpine) |
| `pnpm/24` | `ghcr.io/e2enetworks-oss/pnpm:24-*` | Node 24 + pnpm 11, eslint, prettier, vitest |
| `bun/1` | `ghcr.io/e2enetworks-oss/bun:1-*` | Bun 1.x, git, ssh, curl |

## Tag scheme

Every merge to `main` that touches an image directory publishes two tags:

| Image type | Immutable tag | Moving tag |
|---|---|---|
| Version file | `rust:1.97.1-a1b2c3d` | `rust:latest` |
| Directory variant | `python:3.14-a1b2c3d` | `python:3.14-latest` |
| Bare | `helm-vector:a1b2c3d` | `helm-vector:latest` |

Rust stores its compiler version in `rust/VERSION`. The immutable tag includes that version and the source commit.
The unit tests require `rust/VERSION` to match `RUST_VERSION` in the Dockerfile.

**Consumers should pin the immutable tag.** Use `latest` only for local iteration.

## Updating an image (daily workflow)

1. Edit the Dockerfile in its directory (e.g. `python/3.14/Dockerfile`).
2. Verify locally:
   ```sh
   make build IMAGE=python/3.14
   make test  IMAGE=python/3.14
   ```
3. Open a pull request (PR). CI builds both architectures and saves the layer cache. It does not publish an image.
4. Merge the PR. CI reuses the cache, publishes the immutable tag, and moves the matching latest tag.

When updating Rust, change `rust/VERSION` and `RUST_VERSION` in `rust/Dockerfile` together.

Each PR build pulls fresh base layers. Trivy scans both architectures for every changed image.
It reports all Critical Common Vulnerabilities and Exposures (CVE) findings.
The PR fails when a Critical finding has an available fix.
Findings without an upstream fix remain visible in the build log.

Only directories that changed in the merge get rebuilt and pushed — everything
else is untouched. A `-latest` tag therefore always points at the newest commit
that modified that image, not the newest commit overall.

### How a build is actually assembled

Each image builds once per architecture on its own native runner. Those builds
push **by digest only**, with no tag; a merge job then joins the two digests
into one multi-arch manifest and applies the tags. If either architecture
fails, the merge job refuses to publish rather than shipping a single-arch
image under a tag consumers read as multi-arch.

The layer cache lives in the registry, as a `buildcache-*` tag on each package,
rather than in the GitHub Actions cache. Actions caches are ref-scoped — a run
can read its own ref and the default branch and nothing else — so a pull
request's cache was invisible to the merge build that followed it and every
merge paid for a full cold rebuild. A registry cache has no such scoping.

### Forcing a rebuild

Patch versions float where upstream supports it (`python:3.14-slim`,
`oven/bun:1-slim`), so **rebuilding an unchanged image picks up the latest
patch release**. Rebuild without a code change from the Actions tab
(**Build & Publish** → *Run workflow*), or from the command line:

```sh
gh workflow run build.yml -f images=all           # every image
gh workflow run build.yml -f images=rust,bun/1    # a subset
```

## Consuming an image

```dockerfile
FROM ghcr.io/e2enetworks-oss/rust:1.97.1-a1b2c3d
```

The repository and packages are public. Pulls need no authentication.
Manual pushes need a GitHub Personal Access Token (PAT) with `write:packages`.

```sh
gh auth login          # once, scopes: write:packages
make push IMAGE=bun/1  # logs into ghcr.io for you
```

## Adding a new image

1. Create `<name>/Dockerfile` (or `<name>/<variant>/Dockerfile` for versioned families).
2. Add the directory to `IMAGES` in `make/build.mk`.
3. Add a smoke-test case to the `test` target in `make/build.mk`.
4. Update the table above.
5. PR → merge; CI publishes it.

`IMAGES` is the single source of truth. CI reads it via `make list-dirs` and
generates its own path filters from it, so there is no second list to keep in
sync. A directory nested more than two levels deep (`a/b/c`) is not supported —
the tag scheme has room for one variant segment.

Base images must stay slim: official `-slim`/alpine bases, `--no-install-recommends`
/ `apk --no-cache`, a single `RUN` per concern with layer cleanup, a non-root
user, and a built-in `--version` verification step so a broken image fails the
build instead of shipping.

## Local reference

```sh
make help        # all targets
make list        # images and the tags CI will publish
make lint        # hadolint + actionlint (dockerized, no local deps)
make build-all   # build everything (current arch)
make test-all    # smoke-test everything
```
