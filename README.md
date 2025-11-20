# Modular FFmpeg Docker Build System

A modular, cacheable Docker build system for creating statically-linked FFmpeg binaries with comprehensive codec support.

> **Build Architecture:** Component images (base, av1, x264-x265, etc.) are always built and stored **locally only**. Only the final image can be pushed to a registry. This keeps your registry clean and speeds up builds by reusing local component caches.

## Quick Start

```bash
# Build locally (single platform)
make build

# Build decode-only version
make build-decode

# Build and push to Docker Hub (single platform)
make build-decode-push IMAGE=docker.io/gtstef/ffmpeg:8.0-decode

# Build and push to Docker Hub (single platform)
make build-push IMAGE=docker.io/gtstef/ffmpeg:8.0

# Build for multiple platforms and push
make build-push IMAGE=docker.io/gtstef/ffmpeg:8.0 \
  PLATFORMS=linux/amd64,linux/arm64

# Show all available commands
make help
```

**Supported Platforms:** Currently `linux/amd64` and `linux/arm64` are supported.

**Multi-Platform Note:** Requires containerd image store (default in Docker Desktop) or QEMU emulation.

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

Note: build times are just approximations. Actual build times vary widely based on hardware.

```
                    ┌─────────────────┐
                    │ dockerfile.base │
                    │  Alpine + glib  │
                    |      5 min      |
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
  ┌─────▼─────┐       ┌─────▼─────┐      ┌──────▼──────┐
  │ graphics  │       │    av1    │      │ x264-x265   │
  │  5 min    │       │   5 min   │      │   10 min    │
  └───────────┘       └───────────┘      └─────────────┘
        │                    │                    │
        │             ┌──────▼──────┐             │
        │             │modern-codecs│             │
        │             │   10 min    │             │
        │             └─────────────┘             │
        │                    │                    │
  ┌─────▼─────┐       ┌─────▼─────┐      ┌──────▼──────┐
  │  vpx-avs  │       │   audio   │      │image-formats│
  │   5 min   │       │   5 min   │      │   10 min    │
  └───────────┘       └───────────┘      └─────────────┘
        │                    │                    │
        │             ┌──────▼──────┐             │
        │             │  vaapi      │             │
        │             │   5 min     │             │
        │             └─────────────┘             │
        │                    │                    │
        │             ┌──────▼──────┐             │
        │             │ processing  │             │
        │             │   5 min     │             │
        │             └─────────────┘             │
        │                    │                    │
        └────────────────────┴────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ dockerfile.final│
                    │ FFmpeg + package│
                    |      10 min     |
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

## Common Commands

| Command | Description |
|---------|-------------|
| `make build` | Build full FFmpeg locally |
| `make build-decode` | Build decode-only version (no encoders) |
| `make build-push` | Build and push final image (add PLATFORMS for multi-platform) |
| `make test` | Run tests on built image |
| `make clean` | Remove all local FFmpeg images |
| `make help` | Show all available commands |

### Testing

```bash
# Test the built image
make test-version
make test-encoders
make test-av1

# Or manually
docker run --rm ffmpeg-final:latest -version
docker run --rm ffmpeg-final:latest -buildconf
```

## Build Configurations

### Environment Variables (for Makefile)

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE` | `docker.io/gtstef/ffmpeg:latest` | Full image name for push (has full control) |
| `IMAGE_DECODE` | `docker.io/gtstef/ffmpeg:decode` | Full decode-only image name |
| `REGISTRY` | `docker.io/gtstef` | Docker registry (used to construct IMAGE if not set) |
| `IMAGE_NAME` | `ffmpeg` | Image name without registry/tag |
| `TAG` | `latest` | Tag (used to construct IMAGE if not set) |
| `PLATFORMS` | `linux/amd64,linux/arm64` | Target platforms (supported: `linux/amd64`, `linux/arm64`) |

### Advanced Options (for direct script usage)

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE` | _(empty)_ | Full image name to push (e.g., `docker.io/gtstef/ffmpeg:8.0`) |
| `BUILD_MODE` | `sequential` | Build mode: `sequential`, `parallel` |
| `NO_CACHE` | `false` | Disable Docker layer caching |
| `COMPONENT` | `all` | Build specific component only |
| `PUSH` | `false` | Push final image (components never pushed) |

**Important:** Component images (base, av1, x264-x265, etc.) are **always built and stored locally**. Only the final image can be pushed, and you have full control over its name via the `IMAGE` variable.

## Build Examples

### Local Development

```bash
# Build everything locally
make build

# Build decode-only
make build-decode

# Build with parallel mode (faster)
make build-parallel

# Rebuild from scratch
make rebuild
```

### Push to Registry

```bash
# Build and push final image (full control over image name)
make build-push IMAGE=docker.io/gtstef/ffmpeg:8.0

# Build and push decode-only final image
make build-decode-push IMAGE=docker.io/gtstef/ffmpeg:decode

# Or use convenience variables (constructs docker.io/gtstef/ffmpeg:TAG)
make build-push REGISTRY=docker.io/myuser TAG=8.0

# Note: Components are never pushed, only final images
```

### Multi-Platform Builds

**Prerequisites:** Multi-platform builds require the **containerd image store** (default in Docker Desktop) or QEMU for emulation.

```bash
# Build for multiple platforms and push final image
make build-push IMAGE=docker.io/gtstef/ffmpeg:8.0 \
  PLATFORMS=linux/amd64,linux/arm64

# Build for single alternate platform
make build-push IMAGE=docker.io/gtstef/ffmpeg:8.0 \
  PLATFORMS=linux/arm64

# Build decode-only for multiple platforms
make build-decode-push IMAGE=docker.io/gtstef/ffmpeg:decode \
  PLATFORMS=linux/amd64,linux/arm64

# Direct script usage with full control
IMAGE=docker.io/gtstef/ffmpeg:8.0-decode \
  DECODE_ONLY=true \
  PLATFORMS=linux/amd64,linux/arm64 \
  PUSH=true \
  ./build.sh

# Note: All component and final images are built for specified platforms
# Components remain local, only the final image gets pushed
# Currently supported: linux/amd64, linux/arm64
```

**About Containerd Image Store:**
- Docker Desktop: Enabled by default (Settings → General → "Use containerd for pulling and storing images")
- Docker Engine: Edit `/etc/docker/daemon.json` and add `"features": {"containerd-snapshotter": true}`
- Allows storing multi-platform images locally without needing to push to a registry

### Component Builds

```bash
# Build specific component only
make build-base
make build-av1
make build-x264-x265
make build-final

# Using script directly for more control
COMPONENT=av1 NO_CACHE=true ./build.sh
```

### Maintenance

```bash
# Update source versions
make update

# Fetch source packages
make fetch-sources

# Update and rebuild
make update-and-build

# Clean everything
make clean
```

## Workflow Examples

### Scenario 1: Update SVT-AV1 to Latest Version

```bash
# 1. Update sources
make update
make fetch-sources

# 2. Rebuild only AV1 component
make build-av1

# 3. Rebuild final image
make build-final

# Total time: ~25-30 minutes instead of 60+ minutes
```

### Scenario 2: Test New FFmpeg Configuration

```bash
# 1. Edit docker/dockerfile.final (change FFmpeg ./configure flags)

# 2. Rebuild only final (all components cached)
COMPONENT=final NO_CACHE=true ./build.sh

# Total time: ~10-15 minutes
```

### Scenario 3: Production Release Workflow

```bash
# 1. Build and test locally
make build
make test

# 2. If tests pass, build and push both versions for multiple platforms
make build-push IMAGE=docker.io/yourusername/ffmpeg:8.0 \
  PLATFORMS=linux/amd64,linux/arm64
make build-decode-push IMAGE=docker.io/yourusername/ffmpeg:8.0-decode \
  PLATFORMS=linux/amd64,linux/arm64

# 3. Verify on another machine
docker pull docker.io/yourusername/ffmpeg-final:8.0
docker run --rm docker.io/yourusername/ffmpeg-final:8.0 -version
```

### Scenario 4: CI/CD Pipeline

```bash
# In your CI system (GitHub Actions, GitLab CI, etc.)
make update
make fetch-sources
make build
make ci-test
make ci-build-and-push REGISTRY=ghcr.io/myorg TAG=${CI_COMMIT_TAG}
```

### Scenario 5: Quick Iteration During Development

```bash
# Build with parallel mode for speed
make build-parallel

# Test changes
make test-av1

# Rebuild specific component after changes
COMPONENT=av1 NO_CACHE=true ./build.sh
make build-final
```

## Maintenance & Development

### Update Sources

```bash
# Update to latest versions
make update

# Download source packages
make fetch-sources

# Update and rebuild
make update-and-build
```

### Clean Builds

```bash
# Remove local FFmpeg images
make clean

# Remove all Docker build cache
make clean-all

# Rebuild from scratch
make rebuild
```

## Testing & Debugging

### Quick Tests

```bash
# Run all tests
make test

# Individual tests
make test-version
make test-buildconf
make test-encoders
make test-av1
make test-x265
```

### Manual Testing

```bash
# Version and configuration
docker run --rm ffmpeg-final:latest -version
docker run --rm ffmpeg-final:latest -buildconf
docker run --rm ffmpeg-final:latest -encoders

# Test encoding
docker run --rm ffmpeg-final:latest \
  -f lavfi -i testsrc=duration=1:size=640x480:rate=30 \
  -c:v libsvtav1 -preset 8 -f null -
```

### Debugging

```bash
# Inspect component image
docker run --rm -it ffmpeg-av1:latest /bin/sh

# Check installed libraries
docker run --rm ffmpeg-base:latest ls -la /usr/local/lib/

# View current images
make info
```

## Quick Reference Card

```bash
# Local Development
make build                    # Build locally
make build-decode             # Build decode-only
make build-parallel           # Fast parallel build
make test                     # Run tests
make clean && make build      # Clean rebuild

# Push to Registry
make build-push REGISTRY=docker.io/user TAG=8.0
make build-decode-push REGISTRY=docker.io/user

# Multi-Platform (linux/amd64,linux/arm64 supported)
make build-push IMAGE=docker.io/user/ffmpeg:8.0 \
  PLATFORMS=linux/amd64,linux/arm64
make build-decode-push IMAGE=docker.io/user/ffmpeg:decode \
  PLATFORMS=linux/amd64,linux/arm64

# Direct script usage
IMAGE=docker.io/user/ffmpeg:8.0-decode DECODE_ONLY=true \
  PLATFORMS=linux/amd64,linux/arm64 PUSH=true ./build.sh

# Components
make build-av1                # Build specific component
make build-final              # Build final only

# Maintenance
make update                   # Update versions
make fetch-sources            # Download sources
make info                     # Show configuration
make help                     # Show all commands
```

