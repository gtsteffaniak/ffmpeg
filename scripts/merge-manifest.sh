#!/bin/bash
# Merge per-architecture images into a single multi-arch manifest.
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <target-image> <source-image-1> [source-image-2 ...]" >&2
    exit 1
fi

TARGET="$1"
shift
SOURCES=("$@")

echo "Creating multi-arch manifest: ${TARGET}"
docker buildx imagetools create -t "${TARGET}" "${SOURCES[@]}"
docker buildx imagetools inspect "${TARGET}"

# Per-arch tags are build-time staging only; registry should expose the merged manifest.
for src in "${SOURCES[@]}"; do
    echo "Removing arch-specific tag: ${src}"
    docker buildx imagetools rm "${src}" || true
done
