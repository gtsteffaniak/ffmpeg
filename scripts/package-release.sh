#!/bin/bash
# Extract ffmpeg/ffprobe from a Docker image and package as tar.gz and zip.
set -euo pipefail

IMAGE="${1:?Docker image reference required}"
VERSION="${2:?Version required (e.g. 8.1.1)}"
ARCH="${3:?Architecture required (amd64 or arm64)}"
VARIANT="${4:-}"  # empty = full build, "decode" = decode-only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DIR="${OUTPUT_DIR:-./release-artifacts}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

NAME_PREFIX="ffmpeg"
if [ "${VARIANT}" = "decode" ]; then
    NAME_PREFIX="ffmpeg-decode"
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

echo "Pulling ${IMAGE}"
docker pull "${IMAGE}"

echo "Building Alpine packaging image from ${IMAGE}"
docker build -f "${PROJECT_ROOT}/docker/dockerfile.alpine" \
    --build-arg SOURCE_IMAGE="${IMAGE}" \
    -t "${PKG_IMAGE}" \
    "${PROJECT_ROOT}"

echo "Extracting binaries"
docker create --name "${CONTAINER}" "${PKG_IMAGE}" >/dev/null
docker cp "${CONTAINER}:/usr/local/bin/ffmpeg" "${WORKDIR}/ffmpeg"
docker cp "${CONTAINER}:/usr/local/bin/ffprobe" "${WORKDIR}/ffprobe"
docker rm "${CONTAINER}" >/dev/null
CONTAINER=""

chmod +x "${WORKDIR}/ffmpeg" "${WORKDIR}/ffprobe"

tar -czf "${OUTPUT_DIR}/${BASENAME}.tar.gz" -C "${WORKDIR}" ffmpeg ffprobe
zip -j "${OUTPUT_DIR}/${BASENAME}.zip" "${WORKDIR}/ffmpeg" "${WORKDIR}/ffprobe"

echo "Created ${OUTPUT_DIR}/${BASENAME}.tar.gz"
echo "Created ${OUTPUT_DIR}/${BASENAME}.zip"
