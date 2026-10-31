#!/bin/bash
# Package Windows ffmpeg.exe/ffprobe.exe as a zip archive.
set -euo pipefail

VERSION="${1:?Version required (e.g. 8.1.1)}"

OUTPUT_DIR="${OUTPUT_DIR:-./release-artifacts}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

NAME_PREFIX="ffmpeg"
IMAGE="ffmpeg-windows:latest"

BASENAME="${NAME_PREFIX}-${VERSION}-windows-amd64"
WORKDIR="$(mktemp -d)"
CONTAINER="ffmpeg-win-pkg-$$"

cleanup() {
    docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT

echo "Extracting Windows binaries from ${IMAGE}"
docker create --name "${CONTAINER}" "${IMAGE}" /ffmpeg.exe -version >/dev/null
docker cp "${CONTAINER}:/ffmpeg.exe" "${WORKDIR}/ffmpeg.exe"
docker cp "${CONTAINER}:/ffprobe.exe" "${WORKDIR}/ffprobe.exe"
docker rm "${CONTAINER}" >/dev/null

zip -j "${OUTPUT_DIR}/${BASENAME}.zip" "${WORKDIR}/ffmpeg.exe" "${WORKDIR}/ffprobe.exe"
echo "Created ${OUTPUT_DIR}/${BASENAME}.zip"
