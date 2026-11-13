#!/bin/bash
# build-gpu.sh — local helper for the Debian GPU image (x86_64 only).
#
#   ./scripts/build-gpu.sh                 # build gtstef/ffmpeg:<ver>-gpu locally
#   PUSH=true ./scripts/build-gpu.sh       # build + push to docker.io/gtstef
#   IMAGE=docker.io/gtstef/ffmpeg:9.0.2-gpu ./scripts/build-gpu.sh
#   FFMPEG_VERSION=9.0.2 ./scripts/build-gpu.sh
#
# The image version comes from sources.json (release.ffmpeg_version);
# the Dockerfile reads it directly — no build args. Set FFMPEG_VERSION
# here only to control which sources fetch-sources downloads and which
# image tag to build locally; it must match the catalog.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for GPU image builds" >&2
  exit 1
fi

# shellcheck source=version-gates.sh
source "${SCRIPT_DIR}/version-gates.sh"

# shellcheck disable=SC1091
if [ -z "${FFMPEG_VERSION:-}" ]; then
  FFMPEG_VERSION="$(go run -C tools/catalog . read release.ffmpeg_version)"
fi
export FFMPEG_VERSION

echo "Fetching sources (FFMPEG_VERSION=$FFMPEG_VERSION, DECODE_ONLY=false)..."
make fetch-sources DECODE_ONLY=false

IMAGE="${IMAGE:-docker.io/gtstef/ffmpeg:${FFMPEG_VERSION}-gpu}"
echo "Building GPU image (Debian trixie, linux/amd64) -> $IMAGE (builder discarded; runtime trixie-slim)"
docker build \
  -f docker/dockerfile.gpu \
  --platform linux/amd64 \
  -t "$IMAGE" \
  .

echo "Running smoke checks..."
./scripts/check-gpu.sh "$IMAGE"

if [ "${PUSH:-false}" = "true" ]; then
  echo "Pushing $IMAGE ..."
  docker push "$IMAGE"
fi

echo "Done: $IMAGE"
echo "  The GPU image is x86_64 only; Pi stays on the static Alpine image."
