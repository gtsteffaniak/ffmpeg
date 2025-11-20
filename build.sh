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
REGISTRY=${REGISTRY:-""}
TAG=${TAG:-"latest"}
DECODE_ONLY=${DECODE_ONLY:-"false"}
ALPINE_VERSION=${ALPINE_VERSION:-"alpine:3.22"}
BUILD_MODE=${BUILD_MODE:-"sequential"}  # sequential, parallel, or max-parallel
NO_CACHE=${NO_CACHE:-"false"}
COMPONENT=${COMPONENT:-"all"}
PLATFORMS=${PLATFORMS:-""}  # e.g., "linux/amd64,linux/arm64"
PUSH=${PUSH:-"false"}  # Auto-push when using buildx

# Build from project root
cd "$(dirname "$0")"

# Detect if buildx is available
BUILDX_AVAILABLE=false
if docker buildx version &> /dev/null; then
    BUILDX_AVAILABLE=true
fi

# Determine build method
USE_BUILDX=false
if [ -n "$PLATFORMS" ]; then
    if [ "$BUILDX_AVAILABLE" = false ]; then
        echo -e "${RED}❌ Error: Docker buildx is required for multi-platform builds${NC}"
        echo -e "${YELLOW}Install buildx or remove PLATFORMS variable${NC}"
        exit 1
    fi
    USE_BUILDX=true
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Modular FFmpeg Docker Build System                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Configuration:${NC}"
echo -e "  ${YELLOW}Registry:${NC}      ${REGISTRY:-"(local only)"}"
echo -e "  ${YELLOW}Tag:${NC}           ${TAG}"
echo -e "  ${YELLOW}Decode Only:${NC}   ${DECODE_ONLY}"
echo -e "  ${YELLOW}Alpine:${NC}        ${ALPINE_VERSION}"
echo -e "  ${YELLOW}Build Mode:${NC}    ${BUILD_MODE}"
echo -e "  ${YELLOW}No Cache:${NC}      ${NO_CACHE}"
echo -e "  ${YELLOW}Component:${NC}     ${COMPONENT}"
if [ -n "$PLATFORMS" ]; then
    echo -e "  ${YELLOW}Platforms:${NC}     ${PLATFORMS} (buildx)"
    echo -e "  ${YELLOW}Auto-Push:${NC}     ${PUSH}"
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
    
    echo -e "${BLUE}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} Building: ${CYAN}${image_name}${NC}"
    echo -e "${BLUE}│${NC} ${description}"
    if [ -n "$PLATFORMS" ]; then
        echo -e "${BLUE}│${NC} ${YELLOW}Platforms: ${PLATFORMS}${NC}"
    fi
    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${NC}"
    
    # Create tag list
    # When pushing with buildx, only use registry tags to avoid unauthorized push attempts
    if [ "$USE_BUILDX" = true ] && [ "$PUSH" = "true" ]; then
        if [ -z "$REGISTRY" ]; then
            echo -e "${RED}❌ Error: REGISTRY must be set when using PUSH=true${NC}"
            exit 1
        fi
        TAGS="-t ${REGISTRY}/ffmpeg-${image_name}:${TAG}"
    else
        TAGS="-t ffmpeg-${image_name}:${TAG}"
        if [ -n "$REGISTRY" ]; then
            TAGS="$TAGS -t ${REGISTRY}/ffmpeg-${image_name}:${TAG}"
        fi
    fi
    
    # Build command
    if [ "$USE_BUILDX" = true ]; then
        # Using buildx for multi-platform
        BUILD_CMD="docker buildx build -f docker/${dockerfile} $CACHE_FLAG $TAGS"
        
        # Add platform flag
        BUILD_CMD="$BUILD_CMD --platform ${PLATFORMS}"
        
        # Add push flag if enabled
        if [ "$PUSH" = "true" ]; then
            BUILD_CMD="$BUILD_CMD --push"
        else
            # Load into local docker for single platform, output for multi
            if [[ "$PLATFORMS" == *","* ]]; then
                # Multi-platform: can't load, must push or use registry cache
                echo -e "${YELLOW}⚠️  Multi-platform build without PUSH=true will not be available locally${NC}"
            else
                # Single platform: can load
                BUILD_CMD="$BUILD_CMD --load"
            fi
        fi
    else
        # Using standard docker build
        BUILD_CMD="docker build -f docker/${dockerfile} $CACHE_FLAG $TAGS"
    fi
    
    # Add build args if provided
    if [ -n "$build_args" ]; then
        BUILD_CMD="$BUILD_CMD $build_args"
    fi
    
    # Add context (current directory)
    BUILD_CMD="$BUILD_CMD ."
    
    # Execute build
    if eval $BUILD_CMD; then
        echo -e "${GREEN}✅ ${image_name} built successfully${NC}"
        
        # If we pushed to registry, pull it back and tag locally for subsequent stages
        if [ "$USE_BUILDX" = true ] && [ "$PUSH" = "true" ]; then
            echo -e "${CYAN}📥 Pulling image back for local use...${NC}"
            docker pull ${REGISTRY}/ffmpeg-${image_name}:${TAG}
            docker tag ${REGISTRY}/ffmpeg-${image_name}:${TAG} ffmpeg-${image_name}:latest
            echo -e "${GREEN}✅ Tagged locally as ffmpeg-${image_name}:latest${NC}"
        fi
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

TIER2_IMAGES=(
    "dockerfile.graphics|graphics|--build-arg DECODE_ONLY=${DECODE_ONLY}|Graphics libraries (cairo, pango, harfbuzz)"
    "dockerfile.av1|av1|--build-arg DECODE_ONLY=${DECODE_ONLY}|AV1 codecs (aom, dav1d, SVT-AV1, rav1e)"
    "dockerfile.x264-x265|x264-x265|--build-arg DECODE_ONLY=${DECODE_ONLY}|H.264/265 encoders (x264, x265)"
    "dockerfile.modern-codecs|modern-codecs|--build-arg DECODE_ONLY=${DECODE_ONLY}|Modern codecs (xeve, xevd, vvenc)"
    "dockerfile.vpx-avs|vpx-avs|--build-arg DECODE_ONLY=${DECODE_ONLY}|VP8/9 + AVS codecs (libvpx, davs2, uavs3d)"
    "dockerfile.image-formats|image-formats||Image formats (webp, openjpeg, zimg, libjxl)"
    "dockerfile.audio|audio|--build-arg DECODE_ONLY=${DECODE_ONLY}|Audio codecs (lame, vorbis, rubberband)"
    "dockerfile.vaapi|vaapi||Hardware acceleration (libva, libvpl)"
    "dockerfile.processing|processing|--build-arg DECODE_ONLY=${DECODE_ONLY}|Processing tools (vid.stab, vmaf, libass)"
)

FINAL_IMAGE="dockerfile.final|final|--build-arg DECODE_ONLY=${DECODE_ONLY} --build-arg ALPINE_VERSION=${ALPINE_VERSION}|FFmpeg compilation + testing + final package"

# Build based on component selection
if [ "$COMPONENT" != "all" ]; then
    echo -e "${YELLOW}Building specific component: ${COMPONENT}${NC}"
    echo ""
    
    case $COMPONENT in
        base)
            IFS='|' read -r dockerfile name args desc <<< "$BASE_IMAGE"
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
            IFS='|' read -r dockerfile name args desc <<< "$FINAL_IMAGE"
            build_image "$dockerfile" "$name" "$args" "$desc"
            ;;
        *)
            echo -e "${RED}❌ Unknown component: ${COMPONENT}${NC}"
            echo -e "${YELLOW}Available components:${NC} base, graphics, av1, x264-x265, modern-codecs, vpx-avs, image-formats, audio, vaapi, processing, final"
            exit 1
            ;;
    esac
else
    # Full build based on mode
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}TIER 1: Base Build Environment${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    IFS='|' read -r dockerfile name args desc <<< "$BASE_IMAGE"
    build_image "$dockerfile" "$name" "$args" "$desc"
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}TIER 2: Component Libraries${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ "$BUILD_MODE" = "parallel" ] || [ "$BUILD_MODE" = "max-parallel" ]; then
        echo -e "${YELLOW}Building components in parallel...${NC}"
        echo ""
        build_parallel TIER2_IMAGES
    else
        # Sequential build
        for item in "${TIER2_IMAGES[@]}"; do
            IFS='|' read -r dockerfile name args desc <<< "$item"
            build_image "$dockerfile" "$name" "$args" "$desc"
        done
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}TIER 3: Final FFmpeg Build${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    IFS='|' read -r dockerfile name args desc <<< "$FINAL_IMAGE"
    build_image "$dockerfile" "$name" "$args" "$desc"
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
echo "  ./build.sh"
echo ""
echo "  # Parallel build (faster):"
echo "  BUILD_MODE=parallel ./build.sh"
echo ""
echo "  # Multi-platform build (amd64 + arm64):"
echo "  PLATFORMS=linux/amd64,linux/arm64 REGISTRY=ghcr.io/user PUSH=true ./build.sh"
echo ""
echo "  # Single platform with buildx (amd64 only):"
echo "  PLATFORMS=linux/amd64 ./build.sh"
echo ""
echo "  # Rebuild single component:"
echo "  COMPONENT=av1 ./build.sh"
echo ""
echo "  # Rebuild with no cache:"
echo "  NO_CACHE=true COMPONENT=x264-x265 ./build.sh"
echo ""
echo "  # Decode-only build:"
echo "  DECODE_ONLY=true ./build.sh"
echo ""
echo "  # Multi-platform decode-only:"
echo "  PLATFORMS=linux/amd64,linux/arm64 DECODE_ONLY=true REGISTRY=myregistry PUSH=true ./build.sh"
echo ""

