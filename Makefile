# =============================================================================
# platform-images MAKEFILE - MODULAR STRUCTURE
# =============================================================================

include make/build.mk
include make/quality.mk
.DEFAULT_GOAL := help

help:  ## Show all available Makefile targets
	@echo "platform-images"
	@echo ""
	@echo "Build:"
	@echo "  build IMAGE=<dir>        Build one image locally (current arch, loaded into docker)"
	@echo "  build-all                Build every image locally"
	@echo "  push IMAGE=<dir>         Build + push one image (multi-arch, needs gh auth)"
	@echo "  push-all                 Build + push every image (multi-arch)"
	@echo ""
	@echo "Quality:"
	@echo "  lint                     hadolint + actionlint + shellcheck (dockerized)"
	@echo "  test-unit                Run the bats unit tests for scripts/"
	@echo "  test IMAGE=<dir>         Smoke-test one image (runs it, checks key binaries)"
	@echo "  test-all                 Smoke-test every image"
	@echo ""
	@echo "Info:"
	@echo "  list                     Show images and the tags CI will publish"
	@echo "  list-dirs                Print image directories, one per line (CI reads this)"
	@echo ""
	@echo "Images: $(IMAGES)"
	@echo ""
	@echo "Examples:"
	@echo "  make build IMAGE=python/3.14"
	@echo "  make push IMAGE=bun/1"
