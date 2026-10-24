.PHONY: help build build-local build-push-all build-static build-static-push \
        build-multiplatform update fetch-sources generate-release-body \
        validate-sources clean test test-encoders test-version test-version-gates test-helper test-fetch \
        ci-push-platform ci-push-platform-static ci-merge-manifest ci-merge-manifest-static \
        ci-package-release ci-package-release-static ci-build-component ci-smoke-image ci-push-image \
        ci-build-windows ci-package-windows-release hwtest extract-dist

# Configuration
REGISTRY ?= docker.io/gtstef
IMAGE_NAME ?= ffmpeg
TAG ?= latest
STATIC_TAG ?= static
ALPINE_VERSION ?= alpine:3.22
CATALOG ?= go run -C tools/catalog .
FFMPEG_VERSION ?= $(shell $(CATALOG) read release.ffmpeg_version)
export FFMPEG_VERSION
RELEASE_BODY ?= release-notes.md
PLATFORMS ?= linux/amd64,linux/arm64

# Construct full image names
DEFAULT_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(TAG)
IMAGE ?= $(DEFAULT_IMAGE)
IMAGE_STATIC ?= $(REGISTRY)/$(IMAGE_NAME):$(STATIC_TAG)

ifeq ($(IMAGE),$(DEFAULT_IMAGE))
    STATIC_PUSH_IMAGE := $(IMAGE_STATIC)
else
    STATIC_PUSH_IMAGE := $(IMAGE)
endif

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Show this help message
	@echo "$(CYAN)FFmpeg Docker Build System$(NC)"
	@echo ""
	@echo "$(YELLOW)Common Commands:$(NC)"
	@echo "  make build                    - Build full FFmpeg locally"
	@echo "  make build-static             - Build Alpine static scratch image (software transcode)"
	@echo "  make build-push               - Build and push final image"
	@echo "  make build-push PLATFORMS=... - Build for multiple platforms and push"
	@echo ""
	@echo "$(YELLOW)Note:$(NC) Components are always built locally. Only final images are pushed to registry."
	@echo ""
	@echo "$(YELLOW)All Available Targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-28s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Environment Variables:$(NC)"
	@echo "  IMAGE             - Full image name (default: $(IMAGE))"
	@echo "  IMAGE_STATIC      - Static image name (default: $(IMAGE_STATIC))"
	@echo "  REGISTRY          - Docker registry (default: $(REGISTRY))"
	@echo "  IMAGE_NAME        - Image name without registry (default: $(IMAGE_NAME))"
	@echo "  TAG               - Image tag (default: $(TAG))"
	@echo "  FFMPEG_VERSION    - From sources.json (default: $(FFMPEG_VERSION))"
	@echo "  PLATFORMS         - Target platforms (default: $(PLATFORMS))"
	@echo ""
	@echo "$(YELLOW)Supported Platforms:$(NC) linux/amd64, linux/arm64"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make build-push IMAGE=docker.io/myuser/ffmpeg:8.0"
	@echo "  make build-push IMAGE=docker.io/myuser/ffmpeg:8.0 PLATFORMS=linux/amd64,linux/arm64"
	@echo "  make build-static-push IMAGE=ghcr.io/myuser/ffmpeg:8.0-static PLATFORMS=linux/arm64"
	@echo "  make build-push REGISTRY=docker.io/myuser TAG=8.0  # Uses IMAGE_NAME=ffmpeg"

# ==================== Local Builds ====================

build: ## Build full FFmpeg locally (all encoders enabled)
	@echo "$(CYAN)Building full FFmpeg locally...$(NC)"
	./scripts/build.sh

build-local: build ## Alias for 'build' - build everything locally

build-static: ## Build Alpine static scratch image (software encode, no GPU)
	@echo "$(CYAN)Building static FFmpeg locally...$(NC)"
	BUILD_VARIANT=static ./scripts/build.sh

build-parallel: ## Build locally using parallel mode (faster)
	@echo "$(CYAN)Building with parallel mode...$(NC)"
	BUILD_MODE=parallel ./scripts/build.sh

build-static-parallel: ## Build static with parallel mode
	@echo "$(CYAN)Building static with parallel mode...$(NC)"
	BUILD_VARIANT=static BUILD_MODE=parallel ./scripts/build.sh

# ==================== Push to Registry ====================

build-push: ## Build and push final image (set PLATFORMS for multi-platform)
	@echo "$(CYAN)Building and pushing to: $(IMAGE)$(NC)"
	@if [ -n "$(PLATFORMS)" ]; then \
		echo "$(YELLOW)Building for platforms: $(PLATFORMS)$(NC)"; \
		echo "$(YELLOW)Note: Components will be built locally first$(NC)"; \
	fi
	IMAGE=$(IMAGE) PLATFORMS=$(PLATFORMS) PUSH=true ./scripts/build.sh

build-static-push: ## Build and push static image (set IMAGE and PLATFORMS as needed)
	@echo "$(CYAN)Building and pushing to: $(STATIC_PUSH_IMAGE)$(NC)"
	@if [ -n "$(PLATFORMS)" ]; then \
		echo "$(YELLOW)Building for platforms: $(PLATFORMS)$(NC)"; \
	fi
	BUILD_VARIANT=static IMAGE=$(STATIC_PUSH_IMAGE) PLATFORMS=$(PLATFORMS) PUSH=true ./scripts/build.sh

# ==================== Component Builds ====================

build-base: ## Build only base component
	@echo "$(CYAN)Building base component...$(NC)"
	COMPONENT=base ./scripts/build.sh

build-av1: ## Build only AV1 codecs component
	@echo "$(CYAN)Building AV1 component...$(NC)"
	COMPONENT=av1 ./scripts/build.sh

build-x264-x265: ## Build only x264/x265 component
	@echo "$(CYAN)Building x264-x265 component...$(NC)"
	COMPONENT=x264-x265 ./scripts/build.sh

build-final: ## Build only final FFmpeg component (requires components built)
	@echo "$(CYAN)Building final component...$(NC)"
	COMPONENT=final ./scripts/build.sh

# ==================== Development & Maintenance ====================

update: ## Update source versions in sources.json
	@echo "$(CYAN)Updating source versions...$(NC)"
	$(CATALOG) update

validate-sources: ## Validate sources.json catalog
	@echo "$(CYAN)Validating sources.json...$(NC)"
	$(CATALOG) validate

fetch-sources: ## Fetch/download all source packages
	@echo "$(CYAN)Fetching sources (FFMPEG_VERSION=$(FFMPEG_VERSION))...$(NC)"
	BUILD_VARIANT=$(BUILD_VARIANT) FFMPEG_VERSION=$(FFMPEG_VERSION) ./scripts/fetch-sources.sh

generate-release-body: ## Write GitHub release notes (dependency matrix) to RELEASE_BODY file
	@echo "$(CYAN)Generating release notes (FFMPEG_VERSION=$(FFMPEG_VERSION))...$(NC)"
	FFMPEG_VERSION=$(FFMPEG_VERSION) $(CATALOG) release-body $(RELEASE_BODY)

update-and-build: update fetch-sources build ## Update sources and build locally

clean: ## Remove all local FFmpeg Docker images
	@echo "$(CYAN)Removing local FFmpeg images...$(NC)"
	@docker images | grep "ffmpeg-" | awk '{print $$1":"$$2}' | xargs -r docker rmi -f || true
	@echo "$(GREEN)Clean complete$(NC)"

clean-all: ## Remove all Docker build cache and images
	@echo "$(CYAN)Removing all Docker build cache...$(NC)"
	docker builder prune -af
	@$(MAKE) clean

rebuild: clean build ## Clean and rebuild everything

rebuild-static: clean build-static ## Clean and rebuild static

# ==================== Testing ====================

test: test-version ## Run basic tests on local final image

test-version: ## Show FFmpeg version and build configuration
	@echo "$(CYAN)Testing FFmpeg version...$(NC)"
	docker run --rm ffmpeg-final:latest -version

test-version-gates: ## Run version-gates.sh unit checks
	@echo "$(CYAN)Testing version gates...$(NC)"
	./scripts/test-version-gates.sh

test-helper: ## Run sources.json helper unit tests
	@echo "$(CYAN)Testing helper CLI...$(NC)"
	go test -C tools/catalog . -count=1

test-fetch: ## Run fetch archive validation checks
	@echo "$(CYAN)Testing fetch archive validation...$(NC)"
	./scripts/test-fetch-validation.sh

test-buildconf: ## Show FFmpeg build configuration
	@echo "$(CYAN)Testing FFmpeg build configuration...$(NC)"
	docker run --rm ffmpeg-final:latest -hide_banner -buildconf

test-encoders: ## List all available encoders
	@echo "$(CYAN)Listing FFmpeg encoders...$(NC)"
	docker run --rm ffmpeg-final:latest -encoders

test-codecs: ## List all available codecs
	@echo "$(CYAN)Listing FFmpeg codecs...$(NC)"
	docker run --rm ffmpeg-final:latest -codecs

test-av1: ## Test AV1 encoding
	@echo "$(CYAN)Testing AV1 encoding...$(NC)"
	docker run --rm ffmpeg-final:latest \
		-f lavfi -i testsrc=duration=1:size=640x480:rate=30 \
		-c:v libsvtav1 -preset 8 -f null -

test-x265: ## Test x265 encoding
	@echo "$(CYAN)Testing x265 encoding...$(NC)"
	docker run --rm ffmpeg-final:latest \
		-f lavfi -i testsrc=duration=1:size=640x480:rate=30 \
		-c:v libx265 -preset fast -f null -

# ==================== Docker Hub / Registry ====================

login: ## Login to Docker registry
	@echo "$(CYAN)Logging in to registry...$(NC)"
	@if [ "$(REGISTRY)" = "docker.io/gtstef" ] || [ "$(REGISTRY)" = "docker.io" ]; then \
		docker login; \
	else \
		docker login $(REGISTRY); \
	fi

pull-static: ## Pull static image from registry
	@echo "$(CYAN)Pulling static image...$(NC)"
	docker pull $(IMAGE_STATIC)

pull: ## Pull full image from registry
	@echo "$(CYAN)Pulling full image...$(NC)"
	docker pull $(IMAGE)

# ==================== Buildx Setup ====================

buildx-create: ## Create and setup buildx builder for multi-platform
	@echo "$(CYAN)Creating buildx builder...$(NC)"
	docker buildx create --name ffmpeg-builder --driver docker-container --use || true
	docker buildx inspect --bootstrap

buildx-remove: ## Remove buildx builder
	@echo "$(CYAN)Removing buildx builder...$(NC)"
	docker buildx rm ffmpeg-builder || true

# ==================== CI/CD Helpers ====================

# Per-platform native CI builds (one arch per runner, merged in a follow-up job)
ARCH_SUFFIX ?= amd64
PLATFORM ?= linux/amd64
LOAD_IMAGE ?= false
CI_BUILD_MODE ?= sequential
BUILD_VARIANT ?= full
CI_FINAL_IMAGE ?=
CI_PUSH ?= true

ci-build-component: ## CI: Build one component (COMPONENT=base|graphics|...|final|windows-components|windows)
	@if [ -z "$(COMPONENT)" ]; then echo "COMPONENT is required"; exit 1; fi
	@if [ "$(COMPONENT)" = "final" ] && [ -z "$(CI_FINAL_IMAGE)" ]; then \
		echo "CI_FINAL_IMAGE is required when COMPONENT=final"; exit 1; \
	fi
	@if [ "$(COMPONENT)" = "final" ] || [ "$(COMPONENT)" = "full" ]; then \
		FFMPEG_VERSION=$(FFMPEG_VERSION) BUILD_MODE=$(CI_BUILD_MODE) LOAD_IMAGE=$(LOAD_IMAGE) BUILD_VARIANT=$(BUILD_VARIANT) \
			PLATFORMS=$(PLATFORM) PUSH=$(CI_PUSH) IMAGE=$(CI_FINAL_IMAGE) \
			COMPONENT=$(COMPONENT) ./scripts/build.sh; \
	elif [ "$(COMPONENT)" = "windows-components" ] || [ "$(COMPONENT)" = "windows" ]; then \
		FFMPEG_VERSION=$(FFMPEG_VERSION) BUILD_MODE=$(CI_BUILD_MODE) BUILD_VARIANT=static COMPONENT=$(COMPONENT) ./scripts/build.sh; \
	else \
		FFMPEG_VERSION=$(FFMPEG_VERSION) BUILD_MODE=$(CI_BUILD_MODE) LOAD_IMAGE=$(LOAD_IMAGE) BUILD_VARIANT=$(BUILD_VARIANT) \
			PLATFORMS=$(PLATFORM) PUSH=false COMPONENT=$(COMPONENT) ./scripts/build.sh; \
	fi

ci-smoke-image: ## CI: smoke-test built image (VARIANT=full|static, CI_FINAL_IMAGE, ARCH_SUFFIX)
	@test -n "$(CI_FINAL_IMAGE)"
	./scripts/smoke-test.sh $(VARIANT) $(CI_FINAL_IMAGE) $(ARCH_SUFFIX)

ci-push-image: ## CI: push image after smoke tests
	docker push $(CI_FINAL_IMAGE)

extract-dist: ## Extract linux/windows binaries into .local-build/
	@mkdir -p .local-build
	@echo "$(CYAN)Use 'docker pull' + package-release.sh or build locally first$(NC)"

hwtest: ## Run local GPU smoke tests (docker images or ./.local-build/ffmpeg)
	chmod +x scripts/hwtest.sh
	./scripts/hwtest.sh

ci-push-platform: ## CI: Build and push full image for a single platform (set ARCH_SUFFIX, PLATFORM)
	@echo "$(CYAN)CI: Building full image for $(PLATFORM) -> $(REGISTRY)/$(IMAGE_NAME):$(TAG)-$(ARCH_SUFFIX)$(NC)"
	BUILD_MODE=$(CI_BUILD_MODE) LOAD_IMAGE=$(LOAD_IMAGE) \
		IMAGE=$(REGISTRY)/$(IMAGE_NAME):$(TAG)-$(ARCH_SUFFIX) \
		PLATFORMS=$(PLATFORM) PUSH=true ./scripts/build.sh

ci-push-platform-static: ## CI: Build and push static image for a single platform
	@echo "$(CYAN)CI: Building static image for $(PLATFORM) -> $(REGISTRY)/$(IMAGE_NAME):$(TAG)-static-$(ARCH_SUFFIX)$(NC)"
	BUILD_MODE=$(CI_BUILD_MODE) LOAD_IMAGE=$(LOAD_IMAGE) BUILD_VARIANT=static \
		IMAGE=$(REGISTRY)/$(IMAGE_NAME):$(TAG)-static-$(ARCH_SUFFIX) \
		PLATFORMS=$(PLATFORM) PUSH=true ./scripts/build.sh

ci-merge-manifest: ## CI: Merge per-arch full images into multi-arch manifest
	@echo "$(CYAN)CI: Merging manifest for $(REGISTRY)/$(IMAGE_NAME):$(TAG)$(NC)"
	./scripts/merge-manifest.sh \
		$(REGISTRY)/$(IMAGE_NAME):$(TAG) \
		$(REGISTRY)/$(IMAGE_NAME):$(TAG)-amd64 \
		$(REGISTRY)/$(IMAGE_NAME):$(TAG)-arm64

ci-merge-manifest-static: ## CI: Merge per-arch static images into multi-arch manifest
	@echo "$(CYAN)CI: Merging static manifest for $(REGISTRY)/$(IMAGE_NAME):$(TAG)-static$(NC)"
	./scripts/merge-manifest.sh \
		$(REGISTRY)/$(IMAGE_NAME):$(TAG)-static \
		$(REGISTRY)/$(IMAGE_NAME):$(TAG)-static-amd64 \
		$(REGISTRY)/$(IMAGE_NAME):$(TAG)-static-arm64

ci-package-release: ## CI: Package full ffmpeg/ffprobe binaries for both architectures
	@echo "$(CYAN)CI: Packaging full release binaries for $(TAG)$(NC)"
	PLATFORM=linux/amd64 ./scripts/package-release.sh $(REGISTRY)/$(IMAGE_NAME):$(TAG) $(TAG) amd64
	PLATFORM=linux/arm64 ./scripts/package-release.sh $(REGISTRY)/$(IMAGE_NAME):$(TAG) $(TAG) arm64

ci-package-release-static: ## CI: Package static ffmpeg/ffprobe binaries for both architectures
	@echo "$(CYAN)CI: Packaging static release binaries for $(TAG)$(NC)"
	PLATFORM=linux/amd64 ./scripts/package-release.sh $(REGISTRY)/$(IMAGE_NAME):$(TAG)-static $(TAG) amd64 static
	PLATFORM=linux/arm64 ./scripts/package-release.sh $(REGISTRY)/$(IMAGE_NAME):$(TAG)-static $(TAG) arm64 static

ci-build-windows: ## CI: Build Windows static components + final
	@echo "$(CYAN)CI: Building Windows release$(NC)"
	BUILD_VARIANT=static ./scripts/build-windows.sh

ci-package-windows-release: ## CI: Package full Windows release zip
	@echo "$(CYAN)CI: Packaging Windows full release for $(TAG)$(NC)"
	./scripts/package-windows-release.sh $(TAG)

ci-build-and-push: ## CI: Build and push both full and static versions (local buildx multi-arch)
	@echo "$(CYAN)CI: Building and pushing both versions...$(NC)"
	@$(MAKE) build-push IMAGE=$(IMAGE) PLATFORMS=$(PLATFORMS)
	@$(MAKE) build-static-push IMAGE=$(IMAGE_STATIC) PLATFORMS=$(PLATFORMS)

ci-test: ## CI: Run all tests
	@echo "$(CYAN)CI: Running tests...$(NC)"
	@$(MAKE) test-version
	@$(MAKE) test-av1
	@$(MAKE) test-x265

# ==================== Information ====================

info: ## Show current configuration
	@echo "$(CYAN)Current Configuration:$(NC)"
	@echo "  Image:         $(IMAGE)"
	@echo "  Image Static:  $(IMAGE_STATIC)"
	@echo "  Registry:      $(REGISTRY)"
	@echo "  Image Name:    $(IMAGE_NAME)"
	@echo "  Tag:           $(TAG)"
	@echo "  Static Tag:    $(STATIC_TAG)"
	@echo "  Alpine:        $(ALPINE_VERSION)"
	@echo "  FFmpeg:        $(FFMPEG_VERSION)"
	@echo "  Platforms:     $(PLATFORMS)"
	@echo ""
	@echo "$(CYAN)Local Images:$(NC)"
	@docker images | grep ffmpeg- || echo "  No FFmpeg images found"

list-components: ## List all available components
	@echo "$(CYAN)Available Components:$(NC)"
	@echo "  - base               (Alpine + build tools + glib)"
	@echo "  - graphics           (Cairo, Pango, HarfBuzz)"
	@echo "  - av1                (AV1 codecs)"
	@echo "  - x264-x265          (H.264/H.265 encoders)"
	@echo "  - modern-codecs      (VVC/EVC codecs)"
	@echo "  - vpx-avs            (VP8/9 + AVS codecs)"
	@echo "  - image-formats      (Image format support)"
	@echo "  - audio              (Audio codecs)"
	@echo "  - vaapi              (Hardware acceleration)"
	@echo "  - processing         (Video processing tools)"
	@echo "  - final              (Final FFmpeg build)"

