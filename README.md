# platform-images

Golden CI base images for E2E Networks, built and published to GitHub Packages (ghcr.io).
Every image is multi-arch (`linux/amd64` + `linux/arm64`) and built only when its directory changes.

## Images

| Directory | Published as | Contents |
|---|---|---|
| `python/3.11` | `ghcr.io/e2enetworks-oss/python:3.11-*` | uv, pipenv, ansible, ruff, pyright, semgrep, pytest, Django stack |
| `python/3.14` | `ghcr.io/e2enetworks-oss/python:3.14-*` | same as 3.11 + libxml2/libxslt/libxmlsec headers |
| `rust` | `ghcr.io/e2enetworks-oss/rust:*` | cargo-chef, grcov, sccache, cargo-audit, protobuf |
| `infra-ci` | `ghcr.io/e2enetworks-oss/infra-ci:*` | helm, vector, bash, curl, openssl (alpine) |
| `pnpm/24` | `ghcr.io/e2enetworks-oss/pnpm:24-*` | Node 24 + pnpm 10, eslint, prettier, vitest — **legacy, prefer `bun/1`** |
| `bun/1` | `ghcr.io/e2enetworks-oss/bun:1-*` | Bun 1.x, git, ssh, curl |

## Tag scheme

Every merge to `main` that touches an image directory publishes two tags:

| Tag | Example | Mutability |
|---|---|---|
| `<variant>-<sha7>` | `python:3.14-a1b2c3d` | Immutable — pin this in consumers |
| `<variant>-latest` | `python:3.14-latest` | Moves on every merge |

Images without a variant segment (`rust`, `infra-ci`) get bare tags:
`rust:a1b2c3d`, `rust:latest`.

**Consumers should pin the sha tag.** `-latest` is for convenience and local iteration.

## Updating an image (daily workflow)

1. Edit the Dockerfile in its directory (e.g. `python/3.14/Dockerfile`).
2. Verify locally:
   ```sh
   make build IMAGE=python/3.14
   make test  IMAGE=python/3.14
   ```
3. Open a PR. CI builds the changed image (both architectures, no push).
4. Merge. CI pushes `ghcr.io/e2enetworks-oss/python:3.14-<sha7>` and moves `3.14-latest`.

Only directories that changed in the merge get rebuilt and pushed — everything
else is untouched. A `-latest` tag therefore always points at the newest commit
that modified that image, not the newest commit overall.

Patch versions float where upstream supports it (`python:3.14-slim`,
`oven/bun:1-slim`), so **rebuilding an unchanged image picks up the latest
patch release**. To force a refresh of every image, push an empty commit:
`git commit --allow-empty -m "chore: rebuild all images" && git push`.

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
3. Add a matching path filter to `.github/workflows/build.yml`
   (key rule: path segments joined with `_`, dots become `_` — `python/3.14` → `python_3_14`).
4. Add a smoke-test case to the `test` target in `make/build.mk`.
5. Update the table above.
6. PR → merge; CI publishes it.

Base images must stay slim: official `-slim`/alpine bases, `--no-install-recommends`
/ `apk --no-cache`, a single `RUN` per concern with layer cleanup, a non-root
user, and a built-in `--version` verification step so a broken image fails the
build instead of shipping.

## Migrating from Harbor

Older consumers may still reference `registry.e2enetworks.net/infra/*-ci` tags.
Those are frozen. Point the consumer at the matching `ghcr.io/e2enetworks-oss/*`
sha tag above, verify its CI, and delete the Harbor reference.

## Local reference

```sh
make help        # all targets
make list        # images and the tags CI will publish
make lint        # hadolint + actionlint (dockerized, no local deps)
make build-all   # build everything (current arch)
make test-all    # smoke-test everything
```
