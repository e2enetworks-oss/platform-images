# =============================================================================
# QUALITY — lint Dockerfiles, workflows and shell; run the unit tests
# =============================================================================
# The linters run dockerized so the only local prerequisite is docker.
# bats runs natively: its tests shell out to `make list-dirs`, so it needs this
# repository's make and jq rather than a linter container's.
#   macOS: brew install bats-core · Debian/Ubuntu: apt-get install bats

.PHONY: lint lint-dockerfiles lint-workflows lint-shell test-unit

HADOLINT_IMAGE   ?= ghcr.io/hadolint/hadolint:latest
ACTIONLINT_IMAGE ?= rhysd/actionlint:latest
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable

lint: lint-dockerfiles lint-workflows lint-shell  ## Run every linter

lint-dockerfiles:  ## hadolint every Dockerfile in the repo
	@status=0; \
	for df in $(IMAGES:%=%/Dockerfile); do \
		echo ">> hadolint $$df"; \
		docker run --rm -i $(HADOLINT_IMAGE) hadolint --failure-threshold error - < "$$df" || status=1; \
	done; \
	exit $$status

lint-workflows:  ## actionlint every workflow
	@docker run --rm -v "$(CURDIR):/repo" --workdir /repo $(ACTIONLINT_IMAGE) -color

lint-shell:  ## shellcheck every script
	@echo ">> shellcheck scripts/"
	@docker run --rm -v "$(CURDIR):/mnt" --workdir /mnt $(SHELLCHECK_IMAGE) scripts/*.sh

test-unit:  ## Run the bats unit tests for scripts/
	@command -v bats >/dev/null 2>&1 || { \
		echo "bats not found — brew install bats-core (macOS) or apt-get install bats (Debian)" >&2; \
		exit 1; \
	}
	@bats tests/
