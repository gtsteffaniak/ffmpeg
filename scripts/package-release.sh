#!/bin/bash
# Extract ffmpeg/ffprobe from a Docker image and package as tar.gz and zip.
set -euo pipefail

IMAGE="${1:?Docker image reference required}"
VERSION="${2:?Version required (e.g. 8.1.1)}"
ARCH="${3:?Architecture required (amd64 or arm64)}"
VARIANT="${4:-}"  # empty = full build, "decode" = decode-only

OUTPUT_DIR="${OUTPUT_DIR:-./release-artifacts}"
mkdir -p "${OUTPUT_DIR}"

NAME_PREFIX="ffmpeg"
if [ "${VARIANT}" = "decode" ]; then
    NAME_PREFIX="ffmpeg-decode"
fi

BASENAME="${NAME_PREFIX}-${VERSION}-linux-${ARCH}"
WORKDIR="$(mktemp -d)"
CONTAINER="ffmpeg-pkg-$$"

cleanup() {
    docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT

echo "Extracting binaries from ${IMAGE}"
docker pull "${IMAGE}"
docker create --name "${CONTAINER}" "${IMAGE}" >/dev/null
docker cp "${CONTAINER}:/ffmpeg" "${WORKDIR}/ffmpeg"
docker cp "${CONTAINER}:/ffprobe" "${WORKDIR}/ffprobe"
docker rm "${CONTAINER}" >/dev/null
CONTAINER=""

chmod +x "${WORKDIR}/ffmpeg" "${WORKDIR}/ffprobe"

(
    cd "${WORKDIR}"
    tar -czf "${OUTPUT_DIR}/${BASENAME}.tar.gz" ffmpeg ffprobe
    zip -j "${OUTPUT_DIR}/${BASENAME}.zip" ffmpeg ffprobe
)

echo "Created ${OUTPUT_DIR}/${BASENAME}.tar.gz"
echo "Created ${OUTPUT_DIR}/${BASENAME}.zip"
