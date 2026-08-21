# =============================================================================
# BUILD & REGISTRY — container builds and pushes
# =============================================================================
# Image naming:
#   dir python/3.14  → ghcr.io/e2enetworks-oss/python:3.14-<sha7>, python:3.14-latest
#   dir rust         → ghcr.io/e2enetworks-oss/rust:<version>-<sha7>, rust:latest
# Rust's VERSION file supplies its compiler build argument and tag prefix.
# =============================================================================

.PHONY: build build-all push push-all test test-all list list-dirs _docker_login

REGISTRY   ?= ghcr.io/e2enetworks-oss
GIT_COMMIT := $(if $(GITHUB_SHA),$(shell printf '%.7s' "$(GITHUB_SHA)"),$(shell sha=$$(git rev-parse HEAD 2>/dev/null) && printf '%.7s' "$$sha" || printf 'dev'))
PLATFORMS  ?= linux/amd64,linux/arm64
DOCKER     ?= docker
GH         ?= gh
VERSION_FILE ?= $(IMAGE)/VERSION

# Single source of truth for the image set. Keep in sync with the
# path filters in .github/workflows/build.yml.
IMAGES := python/3.11 python/3.14 rust helm-vector pnpm/24 bun/1.4

# Tag resolution for $(IMAGE):
#   _NAME    = first path segment          (python/3.14 → python)
#   _VARIANT = second path segment, if any (python/3.14 → 3.14)
_NAME    = $(firstword $(subst /, ,$(1)))
_VARIANT = $(word 2,$(subst /, ,$(1)))

# Resolve the version and tags inside the recipe so any helper failure stops the
# build. Make's $(shell ...) discards the command exit status.
define _resolve_tags
	version=$$(scripts/build-matrix.sh image-version "$(IMAGE)" "$(VERSION_FILE)") || exit 1; \
	tags=$$(scripts/build-matrix.sh tags \
		"$(REGISTRY)/$(call _NAME,$(IMAGE))" \
		"$(call _VARIANT,$(IMAGE))" \
		"$(GIT_COMMIT)" \
		"$$version") || exit 1; \
	tag_count=$$(printf '%s\n' "$$tags" | awk 'END { print NR }'); \
	[ "$$tag_count" -eq 2 ] || { echo "expected two image tags, got $$tag_count" >&2; exit 1; }; \
	tag_one=$$(printf '%s\n' "$$tags" | sed -n '1p'); \
	tag_two=$$(printf '%s\n' "$$tags" | sed -n '2p');
endef

define _require_image
	$(if $(IMAGE),,$(error IMAGE is required. Usage: make $(MAKECMDGOALS) IMAGE=<dir> ($(IMAGES))))
	$(if $(filter $(IMAGE),$(IMAGES)),,$(error unknown IMAGE '$(IMAGE)'. Choose from: $(IMAGES)))
endef

build:  ## Build one image locally (current arch)
	$(call _require_image)
	$(call _resolve_tags) \
	DOCKER_BUILDKIT=1 $(DOCKER) buildx build \
		$(IMAGE) \
		-f $(IMAGE)/Dockerfile \
		$(if $(filter rust,$(IMAGE)),--build-arg "RUST_VERSION=$$version",) \
		--tag "$$tag_one" \
		--tag "$$tag_two" \
		--load

build-all:  ## Build every image locally (current arch)
	@for img in $(IMAGES); do \
		$(MAKE) --no-print-directory build IMAGE=$$img || exit 1; \
	done

_docker_login:
	@$(GH) auth token | $(DOCKER) login ghcr.io -u $$($(GH) api user --jq .login) --password-stdin

push: _docker_login  ## Build + push one image (multi-arch)
	$(call _require_image)
	$(call _resolve_tags) \
	DOCKER_BUILDKIT=1 $(DOCKER) buildx build \
		$(IMAGE) \
		-f $(IMAGE)/Dockerfile \
		$(if $(filter rust,$(IMAGE)),--build-arg "RUST_VERSION=$$version",) \
		--tag "$$tag_one" \
		--tag "$$tag_two" \
		--platform $(PLATFORMS) \
		--push

push-all: _docker_login  ## Build + push every image (multi-arch)
	@for img in $(IMAGES); do \
		$(MAKE) --no-print-directory push IMAGE=$$img || exit 1; \
	done

test:  ## Smoke-test one image (runs it, checks key binaries)
	$(call _require_image)
	@case "$(IMAGE)" in \
		python/3.11) cmd="python --version && uv --version && ruff --version && pytest --version" ;; \
		python/3.14) cmd="python --version && uv --version && ruff --version && pytest --version" ;; \
		rust)        cmd="rustc --version && cargo --version && cargo-audit --version" ;; \
		helm-vector) cmd="helm version && vector --version" ;; \
		pnpm/24)     cmd="node --version && pnpm --version && eslint --version" ;; \
		bun/1.4)     cmd="bun --version && git --version" ;; \
		*) echo "no smoke test defined for $(IMAGE) — add a case here" >&2; exit 1 ;; \
	esac; \
	img="$(IMAGE)"; name=$${img%%/*}; rest=$${img#*/}; [ "$$rest" = "$$img" ] && rest=""; \
	if [ -n "$$rest" ]; then tag="$(REGISTRY)/$$name:$$rest-latest"; else tag="$(REGISTRY)/$$img:latest"; fi; \
	echo ">> smoke: $$tag"; \
	docker run --rm --entrypoint /bin/sh "$$tag" -c "$$cmd" || \
	docker run --rm --entrypoint /bin/bash "$$tag" -c "$$cmd"

test-all:  ## Smoke-test every image
	@for img in $(IMAGES); do \
		$(MAKE) --no-print-directory test IMAGE=$$img || exit 1; \
	done

list-dirs:  ## Print image directories, one per line
	@printf '%s\n' $(IMAGES)

list:  ## Show images and the tags CI will publish
	@for img in $(IMAGES); do \
		name=$${img%%/*}; rest=$${img#*/}; [ "$$rest" = "$$img" ] && rest=""; \
		version=$$(scripts/build-matrix.sh image-version "$$img") || exit 1; \
		scripts/build-matrix.sh tags "$(REGISTRY)/$$name" "$$rest" "$(GIT_COMMIT)" "$$version"; \
	done
