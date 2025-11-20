# Modular FFmpeg Docker Build System

A modular, cacheable Docker build system for creating statically-linked FFmpeg binaries with comprehensive codec support.

## Build

# Decode-only build for your current architecture:
DECODE_ONLY=true ./build.sh

# Full encoder build for AMD64 + ARM64, push to Docker Hub:
REGISTRY=docker.io/gtstef TAG=8.0 PLATFORMS="linux/amd64,linux/arm64" PUSH=true ./build.sh

# Decode-only for AMD64 + ARM64:
DECODE_ONLY=true REGISTRY=docker.io/gtstef TAG=8.0-decode PLATFORMS="linux/amd64,linux/arm64" PUSH=true ./build.sh

## File Structure

```
ffmpeg/
├── build.sh                       (main build script - parallel + multi-platform support)
├── docker/
│   ├── dockerfile.base            (Alpine + build tools + glib)
│   ├── dockerfile.graphics        (Cairo, Pango, HarfBuzz)
│   ├── dockerfile.av1             (AV1 codecs: aom, dav1d, SVT-AV1, rav1e)
│   ├── dockerfile.x264-x265       (H.264/H.265 encoders)
│   ├── dockerfile.modern-codecs   (VVC/EVC: xeve, xevd, vvenc)
│   ├── dockerfile.vpx-avs         (VP8/VP9/AVS: libvpx, davs2, uavs3d)
│   ├── dockerfile.image-formats   (Image formats: webp, openjpeg, zimg, libjxl)
│   ├── dockerfile.audio           (Audio codecs: lame, vorbis, ogg, rubberband)
│   ├── dockerfile.vaapi           (Hardware acceleration: libva, libvpl)
│   ├── dockerfile.processing      (Processing: vmaf, vidstab, libass, libmysofa)
│   └── dockerfile.final           (FFmpeg compilation + testing + packaging)
├── Dockerfile                     (original monolithic - kept for reference)
├── checkelf.sh                    (binary validation - used by final stage)
└── src/                           (library source code)
```

## Architecture

The build is split into 11 modular dockerfiles organized in tiers:
```
                    ┌─────────────────┐
                    │ dockerfile.base │  5 min
                    │  Alpine + glib  │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
  ┌─────▼─────┐       ┌─────▼─────┐      ┌──────▼──────┐
  │ graphics  │       │    av1    │      │ x264-x265   │
  │  5 min    │       │  15 min   │      │   12 min    │
  └───────────┘       └───────────┘      └─────────────┘
        │                    │                    │
        │             ┌──────▼──────┐             │
        │             │modern-codecs│             │
        │             │   25 min    │             │
        │             └─────────────┘             │
        │                    │                    │
  ┌─────▼─────┐       ┌─────▼─────┐      ┌──────▼──────┐
  │  vpx-avs  │       │   audio   │      │image-formats│
  │   8 min   │       │   5 min   │      │   15 min    │
  └───────────┘       └───────────┘      └─────────────┘
        │                    │                    │
        │             ┌──────▼──────┐             │
        │             │  vaapi      │             │
        │             │   3 min     │             │
        │             └─────────────┘             │
        │                    │                    │
        │             ┌──────▼──────┐             │
        │             │ processing  │             │
        │             │   8 min     │             │
        │             └─────────────┘             │
        │                    │                    │
        └────────────────────┴────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ dockerfile.final│  10 min
                    │ FFmpeg + package│
                    └─────────────────┘
```
## Components

### Tier 1: Foundation

- **dockerfile.base**: Alpine Linux + build tools + common libraries + glib

### Tier 2: Component Libraries (can build in parallel)

- **dockerfile.graphics**: Cairo, Pango, HarfBuzz (text rendering)
- **dockerfile.av1**: AV1 codecs (aom, dav1d, SVT-AV1, rav1e)
- **dockerfile.x264-x265**: H.264/265 encoders (x264, x265 multilib)
- **dockerfile.modern-codecs**: VVC/EVC codecs (xeve, xevd, vvenc)
- **dockerfile.vpx-avs**: VP8/9 + Chinese AVS codecs (libvpx, davs2, uavs3d)
- **dockerfile.image-formats**: Image codecs (webp, openjpeg, zimg, libjxl)
- **dockerfile.audio**: Audio codecs (lame, vorbis, ogg, rubberband)
- **dockerfile.vaapi**: Hardware acceleration (libva, libvpl)
- **dockerfile.processing**: Video processing (vid.stab, vmaf, libass, lcms2, libmysofa)

### Tier 3: Final Assembly

- **dockerfile.final**: FFmpeg compilation + testing + minimal scratch-based package

## Quick Start

### Build Everything (Sequential)

```bash
cd /path/to/ffmpeg
./build.sh
```

### Build Everything (Parallel - Faster!)

```bash
BUILD_MODE=parallel ./build.sh
```

### Test the Final Image

```bash
docker run --rm ffmpeg-final:latest -version
docker run --rm ffmpeg-final:latest -encoders
docker run --rm ffmpeg-final:latest -buildconf
```

## Build Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAG` | `latest` | Docker image tag |
| `REGISTRY` | _(empty)_ | Docker registry (e.g., `docker.io/user` or `ghcr.io/user`) |
| `DECODE_ONLY` | `false` | Build decode-only version (skips encoders, smaller/faster) |
| `ALPINE_VERSION` | `alpine:3.22` | Base Alpine Linux version |
| `BUILD_MODE` | `sequential` | Build mode: `sequential`, `parallel`, or `max-parallel` |
| `NO_CACHE` | `false` | Disable Docker layer caching |
| `COMPONENT` | `all` | Build specific component only |
| `PLATFORMS` | _(empty)_ | Multi-platform build (e.g., `linux/amd64,linux/arm64`) |
| `PUSH` | `false` | Auto-push to registry (required for multi-platform builds) |

### Build Examples

#### Full build with all defaults (local, single platform)
```bash
./build.sh
```

#### Fast parallel build
```bash
BUILD_MODE=parallel ./build.sh
```

#### Decode-only build (smaller, faster, no encoders)
```bash
DECODE_ONLY=true ./build.sh
```

#### Multi-platform build (AMD64 + ARM64)
```bash
# Requires Docker Buildx and must push to a registry
PLATFORMS="linux/amd64,linux/arm64" REGISTRY=docker.io/yourusername TAG=8.0 PUSH=true ./build.sh
```

#### Decode-only multi-platform build
```bash
DECODE_ONLY=true PLATFORMS="linux/amd64,linux/arm64" REGISTRY=docker.io/yourusername TAG=8.0-decode PUSH=true ./build.sh
```

#### Rebuild specific component (with cache)
```bash
COMPONENT=av1 ./build.sh
```

#### Rebuild specific component (no cache)
```bash
NO_CACHE=true COMPONENT=x264-x265 ./build.sh
```

#### Build with custom tag
```bash
TAG=v8.0 ./build.sh
```

#### Build and tag for registry (local only)
```bash
REGISTRY=ghcr.io/myuser TAG=latest ./build.sh
```

#### Build from specific component onwards
This is useful when you've changed code in a later stage and want to rebuild from that point:
```bash
# Rebuild modern-codecs and final (skips earlier stages)
COMPONENT=modern-codecs ./build.sh
# Then rebuild final
COMPONENT=final ./build.sh
```

## Workflow Examples

### Scenario 1: Update SVT-AV1 to Latest Version

```bash
# 1. Update source in src/SVT-AV1-*/
cd src && rm -rf SVT-AV1-* && wget <new-version> && cd ..

# 2. Rebuild only AV1 component
NO_CACHE=true COMPONENT=av1 ./build.sh

# 3. Rebuild final image
COMPONENT=final ./build.sh

# Total time: ~25-30 minutes instead of 60+ minutes
```

### Scenario 2: Test New FFmpeg Configuration

```bash
# 1. Edit docker/dockerfile.final (change FFmpeg ./configure flags)

# 2. Rebuild only final (all components cached)
NO_CACHE=true COMPONENT=final ./build.sh

# Total time: ~10-15 minutes
```

### Scenario 3: Create Decode-Only Version

```bash
# Build without encoders (faster, smaller)
DECODE_ONLY=true TAG=decode-only ./build.sh

# Result: ffmpeg-final:decode-only
docker run --rm ffmpeg-final:decode-only -version
```

### Scenario 4: Parallel Build for Speed

```bash
# Build all Tier 2 components in parallel
BUILD_MODE=parallel ./build.sh

# Requires: 16GB+ RAM, 4+ CPU cores
# Time savings: ~40-50% faster than sequential
```

### Scenario 5: Multi-Platform Production Build

```bash
# Build for multiple architectures and push to Docker Hub
PLATFORMS="linux/amd64,linux/arm64" \
  REGISTRY=docker.io/yourusername \
  TAG=8.0 \
  PUSH=true \
  ./build.sh

# Then pull and run on any architecture:
docker pull docker.io/yourusername/ffmpeg-final:8.0
docker run --rm docker.io/yourusername/ffmpeg-final:8.0 -version
```

### Scenario 6: Build and Test Locally, Then Push Multi-Platform

```bash
# 1. Build and test locally first (single platform)
./build.sh
docker run --rm ffmpeg-final:latest -version

# 2. If tests pass, build multi-platform and push
PLATFORMS="linux/amd64,linux/arm64" \
  REGISTRY=docker.io/yourusername \
  TAG=8.0 \
  PUSH=true \
  ./build.sh
```

## Maintenance

### Update Sources

```bash
# Run fetch-sources.sh to download latest versions
./fetch-sources.sh

# Then rebuild affected components
NO_CACHE=true ./build.sh
```

### Clean Rebuild

```bash
# Remove all FFmpeg images
docker images | grep ffmpeg- | awk '{print $1":"$2}' | xargs docker rmi

# Rebuild from scratch
NO_CACHE=true ./build.sh
```

### Multi-Platform Build Requirements

For multi-platform builds, you need Docker Buildx configured:

```bash
# Create a new builder instance
docker buildx create --name multiplatform --driver docker-container --use

# Verify it's working
docker buildx inspect --bootstrap

# Now you can build for multiple platforms
PLATFORMS="linux/amd64,linux/arm64" PUSH=true REGISTRY=docker.io/user ./build.sh
```

## 🔍 Debugging

### Inspect Component Image

```bash
# Run bash in component image
docker run --rm -it ffmpeg-av1:latest /bin/sh

# Check installed libraries
ls -la /usr/local/lib/
pkg-config --list-all
```

### Test FFmpeg Binary

```bash
# Version info
docker run --rm ffmpeg-final:latest -version

# Show all codecs
docker run --rm ffmpeg-final:latest -codecs

# Show all encoders
docker run --rm ffmpeg-final:latest -encoders

# Show build configuration
docker run --rm ffmpeg-final:latest -hide_banner -buildconf
```

### Run Test Encode

```bash
# Test AV1 encoding
docker run --rm ffmpeg-final:latest \
  -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
  -c:v libsvtav1 -preset 8 \
  -f null -

# Test x265 encoding
docker run --rm ffmpeg-final:latest \
  -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
  -c:v libx265 -preset medium \
  -f null -
```

## Additional Resources

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Alpine Linux Packages](https://pkgs.alpinelinux.org/packages)
- [Docker Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
