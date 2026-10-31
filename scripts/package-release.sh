#!/bin/bash
# Extract ffmpeg/ffprobe from a Linux Docker image and package as tar.gz.
set -euo pipefail

IMAGE="${1:?Docker image reference required}"
VERSION="${2:?Version required (e.g. 8.1.1)}"
ARCH="${3:?Architecture required (amd64 or arm64)}"
VARIANT="${4:-}"  # empty = full glibc build, "static" = alpine scratch
# Optional: PLATFORM=linux/amd64 to pull a single arch from a multi-arch manifest tag.
PLATFORM="${PLATFORM:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DIR="${OUTPUT_DIR:-./release-artifacts}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

NAME_PREFIX="ffmpeg"
if [ "${VARIANT}" = "static" ]; then
    NAME_PREFIX="ffmpeg-static"
fi

BASENAME="${NAME_PREFIX}-${VERSION}-linux-${ARCH}"
WORKDIR="$(mktemp -d)"
CONTAINER="ffmpeg-pkg-$$"
PKG_IMAGE="ffmpeg-pkg-image-$$"

cleanup() {
    docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    docker rmi -f "${PKG_IMAGE}" >/dev/null 2>&1 || true
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT

echo "Pulling ${IMAGE}${PLATFORM:+ (platform ${PLATFORM})}"
if [ -n "${PLATFORM}" ]; then
    docker pull --platform "${PLATFORM}" "${IMAGE}"
else
    docker pull "${IMAGE}"
fi

if [ "${VARIANT}" = "static" ]; then
  echo "Building Alpine packaging image from scratch static ${IMAGE}"
  docker build -f "${PROJECT_ROOT}/docker/dockerfile.alpine" \
      --build-arg SOURCE_IMAGE="${IMAGE}" \
      -t "${PKG_IMAGE}" \
      "${PROJECT_ROOT}"
  docker create --name "${CONTAINER}" "${PKG_IMAGE}" >/dev/null
  docker cp "${CONTAINER}:/usr/local/bin/ffmpeg" "${WORKDIR}/ffmpeg"
  docker cp "${CONTAINER}:/usr/local/bin/ffprobe" "${WORKDIR}/ffprobe"
else
  echo "Extracting glibc binaries from ${IMAGE}"
  docker create --name "${CONTAINER}" "${IMAGE}" >/dev/null
  docker cp "${CONTAINER}:/usr/local/bin/ffmpeg" "${WORKDIR}/ffmpeg"
  docker cp "${CONTAINER}:/usr/local/bin/ffprobe" "${WORKDIR}/ffprobe"
fi
docker rm "${CONTAINER}" >/dev/null
CONTAINER=""

chmod +x "${WORKDIR}/ffmpeg" "${WORKDIR}/ffprobe"

if [ "${VARIANT}" != "static" ]; then
  ldd "${WORKDIR}/ffmpeg" > "${WORKDIR}/RUNTIME-LIBS.txt" 2>&1 || true
  cat > "${WORKDIR}/README-runtime.txt" <<'EOF'
Full glibc FFmpeg — link dynamically against libva, libvpl, Vulkan, and OpenCL ICDs on the host.
Install Debian bullseye-compatible runtime packages (see docs/docker.md) or use the published Docker image.
NVIDIA video encode requires the NVIDIA Container Toolkit and driver-injected libs.
EOF
  tar -czf "${OUTPUT_DIR}/${BASENAME}.tar.gz" -C "${WORKDIR}" ffmpeg ffprobe README-runtime.txt RUNTIME-LIBS.txt
else
  tar -czf "${OUTPUT_DIR}/${BASENAME}.tar.gz" -C "${WORKDIR}" ffmpeg ffprobe
fi

echo "Created ${OUTPUT_DIR}/${BASENAME}.tar.gz"
