# platform-images

Golden CI base images for E2E Networks, built and published to GitHub Packages (ghcr.io).
Every image is multi-arch (`linux/amd64` + `linux/arm64`) and built only when its directory changes.
Each architecture is built on a native runner — `ubuntu-latest` for amd64, `ubuntu-24.04-arm`
for arm64 — so no build runs under QEMU emulation.

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

| Tag | Example | Mutability |
|---|---|---|
| `<variant>-<sha7>` | `python:3.14-a1b2c3d` | Immutable — pin this in consumers |
| `<variant>-latest` | `python:3.14-latest` | Moves on every merge |

Images without a variant segment (`rust`, `helm-vector`) get bare tags:
`rust:a1b2c3d`, `rust:latest`.

**Consumers should pin the sha tag.** `-latest` is for convenience and local iteration.

## Updating an image (daily workflow)

1. Edit the Dockerfile in its directory (e.g. `python/3.14/Dockerfile`).
2. Verify locally:
   ```sh
   make build IMAGE=python/3.14
   make test  IMAGE=python/3.14
   ```
3. Open a PR. CI builds the changed image on both architectures and publishes
   nothing — but it does write the layer cache.
4. Merge. CI imports that cache, so the merge build is a cache hit rather than a
   second cold build, then pushes `ghcr.io/e2enetworks-oss/python:3.14-<sha7>`
   and moves `3.14-latest`.

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
FROM ghcr.io/e2enetworks-oss/python:3.14-a1b2c3d
```

The repo and packages are public — pulls need no auth. To push manually you
need a GitHub PAT with `write:packages`, via `gh`:

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
