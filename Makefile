.PHONY: help build build-local build-push-all build-decode build-decode-push \
        build-multiplatform build-multiplatform-decode update fetch-sources \
        clean test test-encoders test-version

# Configuration
REGISTRY ?= docker.io/gtstef
IMAGE_NAME ?= ffmpeg
TAG ?= latest
DECODE_TAG ?= decode
ALPINE_VERSION ?= alpine:3.22
PLATFORMS ?= linux/amd64,linux/arm64

# Construct full image names
DEFAULT_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(TAG)
IMAGE ?= $(DEFAULT_IMAGE)
IMAGE_DECODE ?= $(REGISTRY)/$(IMAGE_NAME):$(DECODE_TAG)

# For decode-push: use IMAGE if explicitly provided, otherwise IMAGE_DECODE
ifeq ($(IMAGE),$(DEFAULT_IMAGE))
    DECODE_PUSH_IMAGE := $(IMAGE_DECODE)
else
    DECODE_PUSH_IMAGE := $(IMAGE)
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
	@echo "  make build-decode             - Build decode-only version locally"
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
	@echo "  IMAGE_DECODE      - Decode image name (default: $(IMAGE_DECODE))"
	@echo "  REGISTRY          - Docker registry (default: $(REGISTRY))"
	@echo "  IMAGE_NAME        - Image name without registry (default: $(IMAGE_NAME))"
	@echo "  TAG               - Image tag (default: $(TAG))"
	@echo "  PLATFORMS         - Target platforms (default: $(PLATFORMS))"
	@echo ""
	@echo "$(YELLOW)Supported Platforms:$(NC) linux/amd64, linux/arm64"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make build-push IMAGE=docker.io/myuser/ffmpeg:8.0"
	@echo "  make build-push IMAGE=docker.io/myuser/ffmpeg:8.0 PLATFORMS=linux/amd64,linux/arm64"
	@echo "  make build-decode-push IMAGE=ghcr.io/myuser/ffmpeg:8.0-decode PLATFORMS=linux/arm64"
	@echo "  make build-push REGISTRY=docker.io/myuser TAG=8.0  # Uses IMAGE_NAME=ffmpeg"

# ==================== Local Builds ====================

build: ## Build full FFmpeg locally (all encoders enabled)
	@echo "$(CYAN)Building full FFmpeg locally...$(NC)"
	./build.sh

build-local: build ## Alias for 'build' - build everything locally

build-decode: ## Build decode-only version locally (no encoders)
	@echo "$(CYAN)Building decode-only FFmpeg locally...$(NC)"
	DECODE_ONLY=true ./build.sh

build-parallel: ## Build locally using parallel mode (faster)
	@echo "$(CYAN)Building with parallel mode...$(NC)"
	BUILD_MODE=parallel ./build.sh

build-decode-parallel: ## Build decode-only with parallel mode
	@echo "$(CYAN)Building decode-only with parallel mode...$(NC)"
	DECODE_ONLY=true BUILD_MODE=parallel ./build.sh

# ==================== Push to Registry ====================

build-push: ## Build and push final image (set PLATFORMS for multi-platform)
	@echo "$(CYAN)Building and pushing to: $(IMAGE)$(NC)"
	@if [ -n "$(PLATFORMS)" ]; then \
		echo "$(YELLOW)Building for platforms: $(PLATFORMS)$(NC)"; \
		echo "$(YELLOW)Note: Components will be built locally first$(NC)"; \
	fi
	IMAGE=$(IMAGE) PLATFORMS=$(PLATFORMS) PUSH=true ./build.sh

build-decode-push: ## Build and push decode-only (set IMAGE and PLATFORMS as needed)
	@echo "$(CYAN)Building and pushing to: $(DECODE_PUSH_IMAGE)$(NC)"
	@if [ -n "$(PLATFORMS)" ]; then \
		echo "$(YELLOW)Building for platforms: $(PLATFORMS)$(NC)"; \
		echo "$(YELLOW)Note: Components will be built locally first$(NC)"; \
	fi
	DECODE_ONLY=true IMAGE=$(DECODE_PUSH_IMAGE) PLATFORMS=$(PLATFORMS) PUSH=true ./build.sh

# ==================== Component Builds ====================

build-base: ## Build only base component
	@echo "$(CYAN)Building base component...$(NC)"
	COMPONENT=base ./build.sh

build-av1: ## Build only AV1 codecs component
	@echo "$(CYAN)Building AV1 component...$(NC)"
	COMPONENT=av1 ./build.sh

build-x264-x265: ## Build only x264/x265 component
	@echo "$(CYAN)Building x264-x265 component...$(NC)"
	COMPONENT=x264-x265 ./build.sh

build-final: ## Build only final FFmpeg component (requires components built)
	@echo "$(CYAN)Building final component...$(NC)"
	COMPONENT=final ./build.sh

# ==================== Development & Maintenance ====================

update: ## Update source versions using helper program
	@echo "$(CYAN)Updating source versions...$(NC)"
	@if [ -f helper.go ]; then \
		go run helper.go; \
	else \
		echo "$(YELLOW)helper.go not found - skipping update$(NC)"; \
	fi

fetch-sources: ## Fetch/download all source packages
	@echo "$(CYAN)Fetching source packages...$(NC)"
	@if [ -f fetch-sources.sh ]; then \
		./fetch-sources.sh; \
	else \
		echo "$(YELLOW)fetch-sources.sh not found$(NC)"; \
	fi

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

rebuild-decode: clean build-decode ## Clean and rebuild decode-only

# ==================== Testing ====================

test: test-version ## Run basic tests on local final image

test-version: ## Show FFmpeg version and build configuration
	@echo "$(CYAN)Testing FFmpeg version...$(NC)"
	docker run --rm ffmpeg-final:latest -version

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

pull-decode: ## Pull decode-only image from registry
	@echo "$(CYAN)Pulling decode-only image...$(NC)"
	docker pull $(IMAGE_DECODE)

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

ci-build-and-push: ## CI: Build and push both full and decode versions
	@echo "$(CYAN)CI: Building and pushing both versions...$(NC)"
	@$(MAKE) build-push IMAGE=$(IMAGE) PLATFORMS=$(PLATFORMS)
	@$(MAKE) build-decode-push IMAGE=$(IMAGE_DECODE) PLATFORMS=$(PLATFORMS)

ci-test: ## CI: Run all tests
	@echo "$(CYAN)CI: Running tests...$(NC)"
	@$(MAKE) test-version
	@$(MAKE) test-av1
	@$(MAKE) test-x265

# ==================== Information ====================

info: ## Show current configuration
	@echo "$(CYAN)Current Configuration:$(NC)"
	@echo "  Image:         $(IMAGE)"
	@echo "  Image Decode:  $(IMAGE_DECODE)"
	@echo "  Registry:      $(REGISTRY)"
	@echo "  Image Name:    $(IMAGE_NAME)"
	@echo "  Tag:           $(TAG)"
	@echo "  Decode Tag:    $(DECODE_TAG)"
	@echo "  Alpine:        $(ALPINE_VERSION)"
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

