# =============================================================================
# QUALITY — lint Dockerfiles and GitHub Actions workflows
# =============================================================================
# Both linters run dockerized so the only local prerequisite is docker.

.PHONY: lint lint-dockerfiles lint-workflows

HADOLINT_IMAGE  ?= ghcr.io/hadolint/hadolint:latest
ACTIONLINT_IMAGE ?= rhysd/actionlint:latest

lint: lint-dockerfiles lint-workflows  ## Run every linter

lint-dockerfiles:  ## hadolint every Dockerfile in the repo
	@status=0; \
	for df in $(IMAGES:%=%/Dockerfile); do \
		echo ">> hadolint $$df"; \
		docker run --rm -i $(HADOLINT_IMAGE) hadolint --failure-threshold error - < "$$df" || status=1; \
	done; \
	exit $$status

lint-workflows:  ## actionlint every workflow
	@docker run --rm -v "$(CURDIR):/repo" --workdir /repo $(ACTIONLINT_IMAGE) -color
