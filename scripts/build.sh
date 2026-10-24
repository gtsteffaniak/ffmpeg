#!/bin/bash

# Modular FFmpeg Docker Build Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
IMAGE=${IMAGE:-""}  # Full image name (e.g., docker.io/user/ffmpeg:8.0)
DECODE_ONLY=${DECODE_ONLY:-"false"}
BUILD_VARIANT=${BUILD_VARIANT:-""}
ALPINE_VERSION=${ALPINE_VERSION:-"alpine:3.22"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=variant.sh
source "${SCRIPT_DIR}/variant.sh"
normalize_build_variant
export BUILD_VARIANT
# Static image always includes software encoders (legacy DECODE_ONLY skipped them).
if [ "$BUILD_VARIANT" = "static" ]; then
    DECODE_ONLY=false
fi
export DECODE_ONLY
read_ffmpeg_version() {
    (cd "$REPO_ROOT" && go run -C tools/catalog . read release.ffmpeg_version)
}
FFMPEG_VERSION="${FFMPEG_VERSION:-$(read_ffmpeg_version)}"
export FFMPEG_VERSION
GATED_BUILD_ARGS="--build-arg BUILD_VARIANT=${BUILD_VARIANT} --build-arg DECODE_ONLY=${DECODE_ONLY} --build-arg FFMPEG_VERSION=${FFMPEG_VERSION}"
BUILD_MODE=${BUILD_MODE:-"sequential"}  # sequential, parallel, or max-parallel
NO_CACHE=${NO_CACHE:-"false"}
COMPONENT=${COMPONENT:-"all"}
PLATFORMS=${PLATFORMS:-""}  # e.g., "linux/amd64,linux/arm64"
PUSH=${PUSH:-"false"}  # Push final image only (components are never pushed)
LOAD_IMAGE=${LOAD_IMAGE:-"true"}  # Load image locally after single-platform push (set false in CI)

# Parse IMAGE into components if provided
if [ -n "$IMAGE" ]; then
    # Extract tag (after last :)
    if [[ "$IMAGE" == *:* ]]; then
        PUSH_TAG="${IMAGE##*:}"
        PUSH_IMAGE_NO_TAG="${IMAGE%:*}"
    else
        PUSH_TAG="latest"
        PUSH_IMAGE_NO_TAG="$IMAGE"
    fi
else
    PUSH_TAG=""
    PUSH_IMAGE_NO_TAG=""
fi

# Build from project root
cd "$REPO_ROOT"

# Detect if buildx is available
BUILDX_AVAILABLE=false
if docker buildx version &> /dev/null; then
    BUILDX_AVAILABLE=true
fi

# Determine build method
# Single-platform builds use classic `docker build` so locally tagged component
# images (ffmpeg-base:latest, etc.) remain visible to later stages. The buildx
# container driver runs in an isolated builder and tries to pull those from a registry.
USE_BUILDX=false
if [ -n "$PLATFORMS" ]; then
    if [ "$BUILDX_AVAILABLE" = false ]; then
        echo -e "${RED}❌ Error: Docker buildx is required for multi-platform builds${NC}"
        echo -e "${YELLOW}Install buildx or remove PLATFORMS variable${NC}"
        exit 1
    fi
    if [[ "$PLATFORMS" == *","* ]]; then
        USE_BUILDX=true
    fi
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Modular FFmpeg Docker Build System                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Configuration:${NC}"
if [ -n "$IMAGE" ]; then
    echo -e "  ${YELLOW}Push Image:${NC}    ${IMAGE}"
else
    echo -e "  ${YELLOW}Build:${NC}         Local only"
fi
echo -e "  ${YELLOW}Variant:${NC}       ${BUILD_VARIANT}"
echo -e "  ${YELLOW}FFmpeg:${NC}        ${FFMPEG_VERSION}"
echo -e "  ${YELLOW}Alpine:${NC}        ${ALPINE_VERSION}"
echo -e "  ${YELLOW}Build Mode:${NC}    ${BUILD_MODE}"
echo -e "  ${YELLOW}No Cache:${NC}      ${NO_CACHE}"
echo -e "  ${YELLOW}Component:${NC}     ${COMPONENT}"
if [ -n "$PLATFORMS" ]; then
    if [ "$USE_BUILDX" = true ]; then
        echo -e "  ${YELLOW}Platforms:${NC}     ${PLATFORMS} (buildx)"
    else
        echo -e "  ${YELLOW}Platforms:${NC}     ${PLATFORMS} (docker build)"
    fi
fi
echo ""

# Set cache flag
CACHE_FLAG=""
if [ "$NO_CACHE" = "true" ]; then
    CACHE_FLAG="--no-cache"
fi

# Function to build and tag image
build_image() {
    local dockerfile=$1
    local image_name=$2
    local build_args=$3
    local description=$4

    # Only final image can be pushed, but all images use multi-platform if specified
    local should_push="false"
    if { [ "$image_name" = "final" ] || [ "$image_name" = "full" ]; } && [ "$PUSH" = "true" ]; then
        should_push="true"
    fi

    echo -e "${BLUE}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} Building: ${CYAN}${image_name}${NC}"
    echo -e "${BLUE}│${NC} ${description}"
    if [ -n "$PLATFORMS" ]; then
        echo -e "${BLUE}│${NC} ${YELLOW}Platforms: ${PLATFORMS}${NC}"
    fi
    if [ "$should_push" = "true" ] && [ -n "$IMAGE" ]; then
        echo -e "${BLUE}│${NC} ${GREEN}Will push to: ${IMAGE}${NC}"
    else
        echo -e "${BLUE}│${NC} ${YELLOW}Local only (not pushed)${NC}"
    fi
    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${NC}"

    # Create tag list
    # When pushing, only use the registry tag to avoid attempting to push local tag
    # When not pushing, use local tag
    if [ "$should_push" = "true" ]; then
        if [ -z "$IMAGE" ]; then
            echo -e "${RED}❌ Error: IMAGE must be set when PUSH=true${NC}"
            exit 1
        fi
        # Only use registry tag when pushing
        TAGS="-t ${IMAGE}"
    else
        # Use local tag for components and local-only builds
        TAGS="-t ffmpeg-${image_name}:latest"
    fi

    # Build command
    if [ "$USE_BUILDX" = true ]; then
        # Using buildx
        BUILD_CMD="docker buildx build -f docker/${dockerfile} $CACHE_FLAG $TAGS"

        # Add platform flag if specified
        if [ -n "$PLATFORMS" ]; then
            BUILD_CMD="$BUILD_CMD --platform ${PLATFORMS}"
        fi

        # Add output flags
        if [ "$should_push" = "true" ]; then
            # Pushing final image to registry
            if [[ "$PLATFORMS" == *","* ]]; then
                # Multi-platform push: only push, don't load (can't load multi-platform without containerd)
                BUILD_CMD="$BUILD_CMD --push"
                echo -e "${CYAN}📦 Multi-platform image will be pushed to registry${NC}"
                echo -e "${CYAN}   Pull locally with: docker pull ${IMAGE}${NC}"
            else
                # Single platform: push and optionally load (CI sets LOAD_IMAGE=false)
                if [ "$LOAD_IMAGE" = "true" ]; then
                    BUILD_CMD="$BUILD_CMD --push --load"
                else
                    BUILD_CMD="$BUILD_CMD --push"
                fi
            fi
        else
            # Building locally without push (components or final)
            BUILD_CMD="$BUILD_CMD --load"
            if [[ "$PLATFORMS" == *","* ]]; then
                echo -e "${CYAN}📦 Building multi-platform locally (requires containerd image store)${NC}"
            fi
        fi

    else
        # Using standard docker build (shares local image store with prior stages)
        BUILD_CMD="docker build -f docker/${dockerfile} $CACHE_FLAG $TAGS"
        if [ -n "$PLATFORMS" ]; then
            BUILD_CMD="$BUILD_CMD --platform ${PLATFORMS}"
        fi
    fi

    # Add build args if provided
    if [ -n "$build_args" ]; then
        BUILD_CMD="$BUILD_CMD $build_args"
    fi

    # Add context (current directory)
    BUILD_CMD="$BUILD_CMD ."

    # Execute build
    if eval $BUILD_CMD; then
        if [ "$should_push" = "true" ] && [ "$USE_BUILDX" = false ]; then
            docker push "${IMAGE}"
        fi
        echo -e "${GREEN}✅ ${image_name} built successfully${NC}"
    else
        echo -e "${RED}❌ ${image_name} build failed${NC}"
        exit 1
    fi
    echo ""
}

# Function to build multiple images in parallel
build_parallel() {
    local -n arr=$1
    local pids=()

    # Note: Parallel builds with buildx can be tricky due to shared builder state
    if [ "$USE_BUILDX" = true ]; then
        echo -e "${YELLOW}⚠️  Warning: Parallel builds with buildx may be unstable${NC}"
        echo -e "${YELLOW}    Consider using BUILD_MODE=sequential for multi-platform${NC}"
        echo ""
    fi

    for item in "${arr[@]}"; do
        IFS='|' read -r dockerfile name args desc <<< "$item"
        build_image "$dockerfile" "$name" "$args" "$desc" &
        pids+=($!)
    done

    # Wait for all builds to complete
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            echo -e "${RED}❌ Parallel build failed${NC}"
            exit 1
        fi
    done
}

# Build definitions: dockerfile|image_name|build_args|description
BASE_IMAGE="dockerfile.base|base||Base build environment with Alpine + tools + glib"
DEBIAN_BASE_IMAGE="dockerfile.debian-base|debian-base||Debian bullseye glibc build environment (full image)"

TIER2_IMAGES=(
    "dockerfile.graphics|graphics|${GATED_BUILD_ARGS}|Graphics libraries (cairo, pango, harfbuzz)"
    "dockerfile.av1|av1|${GATED_BUILD_ARGS}|AV1 codecs (aom, dav1d, SVT-AV1, rav1e)"
    "dockerfile.x264-x265|x264-x265|${GATED_BUILD_ARGS}|H.264/265 encoders (x264, x265)"
    "dockerfile.modern-codecs|modern-codecs|${GATED_BUILD_ARGS}|Modern codecs (xeve, xevd, vvenc)"
    "dockerfile.vpx-avs|vpx-avs|${GATED_BUILD_ARGS}|VP8/9 + AVS codecs (libvpx, davs2, uavs3d)"
    "dockerfile.image-formats|image-formats|${GATED_BUILD_ARGS}|Image formats (webp, openjpeg, zimg, libjxl)"
    "dockerfile.audio|audio|${GATED_BUILD_ARGS}|Audio codecs (lame, vorbis, rubberband)"
    "dockerfile.processing|processing|${GATED_BUILD_ARGS}|Processing tools (vid.stab, vmaf, libass)"
)

FINAL_STATIC_IMAGE="dockerfile.final|final|${GATED_BUILD_ARGS} --build-arg ALPINE_VERSION=${ALPINE_VERSION}|Alpine static scratch image (software + v4l2m2m)"
FULL_GLIBC_IMAGE="dockerfile.full|full|${GATED_BUILD_ARGS} --build-arg DEBIAN_VERSION=bullseye|Debian glibc GPU-capable runtime image"

# Build based on component selection
if [ "$COMPONENT" != "all" ]; then
    echo -e "${YELLOW}Building specific component: ${COMPONENT}${NC}"
    echo ""

    case $COMPONENT in
        base)
            IFS='|' read -r dockerfile name args desc <<< "$BASE_IMAGE"
            build_image "$dockerfile" "$name" "$args" "$desc"
            ;;
        debian-base)
            IFS='|' read -r dockerfile name args desc <<< "$DEBIAN_BASE_IMAGE"
            build_image "$dockerfile" "$name" "$args" "$desc"
            ;;
        full)
            IFS='|' read -r dockerfile name args desc <<< "$FULL_GLIBC_IMAGE"
            build_image "$dockerfile" "$name" "$args" "$desc"
            ;;
        graphics|av1|x264-x265|modern-codecs|vpx-avs|image-formats|audio|vaapi|processing)
            # Find and build the specific component
            for item in "${TIER2_IMAGES[@]}"; do
                IFS='|' read -r dockerfile name args desc <<< "$item"
                if [ "$name" = "$COMPONENT" ]; then
                    build_image "$dockerfile" "$name" "$args" "$desc"
                    break
                fi
            done
            ;;
        final)
            BUILD_VARIANT=static export BUILD_VARIANT
            GATED_BUILD_ARGS="--build-arg BUILD_VARIANT=static --build-arg DECODE_ONLY=false --build-arg FFMPEG_VERSION=${FFMPEG_VERSION}"
            FINAL_STATIC_IMAGE="dockerfile.final|final|${GATED_BUILD_ARGS} --build-arg ALPINE_VERSION=${ALPINE_VERSION}|Alpine static scratch image"
            IFS='|' read -r dockerfile name args desc <<< "$FINAL_STATIC_IMAGE"
            build_image "$dockerfile" "$name" "$args" "$desc"
            ;;
        windows-components)
            components_tag="ffmpeg-windows-components:latest"
            echo -e "${BLUE}Building Windows components -> ${components_tag}${NC}"
            docker build -f docker/dockerfile.windows-components $CACHE_FLAG \
                --build-arg BUILD_VARIANT=static \
                -t "${components_tag}" .
            echo -e "${GREEN}✅ windows-components built successfully${NC}"
            echo ""
            ;;
        windows)
            components_tag="ffmpeg-windows-components:latest"
            windows_tag="ffmpeg-windows:latest"
            echo -e "${BLUE}Building Windows final -> ${windows_tag}${NC}"
            docker build -f docker/dockerfile.windows $CACHE_FLAG \
                --build-arg BUILD_VARIANT=static \
                --build-arg COMPONENTS_IMAGE="${components_tag}" \
                -t "${windows_tag}" .
            echo -e "${GREEN}✅ windows built successfully${NC}"
            echo ""
            ;;
        *)
            echo -e "${RED}❌ Unknown component: ${COMPONENT}${NC}"
            echo -e "${YELLOW}Available components:${NC} base, debian-base, graphics, av1, x264-x265, modern-codecs, vpx-avs, image-formats, audio, vaapi, processing, final, full, windows-components, windows"
            exit 1
            ;;
    esac
else
    if [ "$BUILD_VARIANT" = "full" ]; then
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}Debian glibc full image (GPU-capable runtime)${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        IFS='|' read -r dockerfile name args desc <<< "$DEBIAN_BASE_IMAGE"
        build_image "$dockerfile" "$name" "$args" "$desc"
        IFS='|' read -r dockerfile name args desc <<< "$FULL_GLIBC_IMAGE"
        build_image "$dockerfile" "$name" "$args" "$desc"
    else
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}TIER 1: Alpine static base${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        IFS='|' read -r dockerfile name args desc <<< "$BASE_IMAGE"
        build_image "$dockerfile" "$name" "$args" "$desc"

        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}TIER 2: Component Libraries (no GPU userspace)${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo ""

        if [ "$BUILD_MODE" = "parallel" ] || [ "$BUILD_MODE" = "max-parallel" ]; then
            build_parallel TIER2_IMAGES
        else
            for item in "${TIER2_IMAGES[@]}"; do
                IFS='|' read -r dockerfile name args desc <<< "$item"
                build_image "$dockerfile" "$name" "$args" "$desc"
            done
        fi

        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}TIER 3: Static scratch image${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        echo ""
        BUILD_VARIANT=static export BUILD_VARIANT
        FINAL_STATIC_IMAGE="dockerfile.final|final|${GATED_BUILD_ARGS} --build-arg ALPINE_VERSION=${ALPINE_VERSION}|Alpine static scratch image"
        IFS='|' read -r dockerfile name args desc <<< "$FINAL_STATIC_IMAGE"
        build_image "$dockerfile" "$name" "$args" "$desc"
    fi
fi

# Summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ Build Complete!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$COMPONENT" = "all" ]; then
    echo -e "${CYAN}Available images:${NC}"
    echo "  • ffmpeg-base:${TAG}"
    echo "  • ffmpeg-graphics:${TAG}"
    echo "  • ffmpeg-av1:${TAG}"
    echo "  • ffmpeg-x264-x265:${TAG}"
    echo "  • ffmpeg-modern-codecs:${TAG}"
    echo "  • ffmpeg-vpx-avs:${TAG}"
    echo "  • ffmpeg-image-formats:${TAG}"
    echo "  • ffmpeg-audio:${TAG}"
    echo "  • ffmpeg-vaapi:${TAG}"
    echo "  • ffmpeg-processing:${TAG}"
    echo "  • ffmpeg-final:${TAG}"
    echo ""

    if [ "$USE_BUILDX" = false ] || [ "$PUSH" = false ]; then
        echo -e "${YELLOW}Quick test:${NC}"
        echo "  docker run --rm ffmpeg-final:${TAG} -version"
        echo ""
    fi
fi

if [ -n "$REGISTRY" ]; then
    if [ "$PUSH" = false ]; then
        echo -e "${YELLOW}To push to registry:${NC}"
        if [ "$COMPONENT" = "all" ]; then
            echo "  docker push ${REGISTRY}/ffmpeg-final:${TAG}"
            echo ""
            echo -e "${YELLOW}Or push all components:${NC}"
            echo "  docker images --format '{{.Repository}}:{{.Tag}}' | grep ${REGISTRY}/ffmpeg- | xargs -n1 docker push"
        else
            echo "  docker push ${REGISTRY}/ffmpeg-${COMPONENT}:${TAG}"
        fi
        echo ""
    else
        echo -e "${GREEN}✅ Images pushed to ${REGISTRY}${NC}"
        echo ""
    fi
fi

echo -e "${CYAN}Build examples:${NC}"
echo "  # Full sequential build:"
echo "  ./scripts/build.sh"
echo ""
echo "  # Parallel build (faster):"
echo "  BUILD_MODE=parallel ./scripts/build.sh"
echo ""
echo "  # Multi-platform build (amd64 + arm64):"
echo "  PLATFORMS=linux/amd64,linux/arm64 REGISTRY=ghcr.io/user PUSH=true ./scripts/build.sh"
echo ""
echo "  # Single platform with buildx (amd64 only):"
echo "  PLATFORMS=linux/amd64 ./scripts/build.sh"
echo ""
echo "  # Rebuild single component:"
echo "  COMPONENT=av1 ./scripts/build.sh"
echo ""
echo "  # Rebuild with no cache:"
echo "  NO_CACHE=true COMPONENT=x264-x265 ./scripts/build.sh"
echo ""
echo "  # Static scratch build:"
echo "  BUILD_VARIANT=static ./scripts/build.sh"
echo ""
echo "  # Multi-platform static:"
echo "  PLATFORMS=linux/amd64,linux/arm64 BUILD_VARIANT=static REGISTRY=myregistry PUSH=true ./scripts/build.sh"
echo ""

