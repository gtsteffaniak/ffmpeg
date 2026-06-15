#!/bin/bash
# Merge per-architecture images into a single multi-arch manifest.
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <target-image> <source-image-1> [source-image-2 ...]" >&2
    exit 1
fi

TARGET="$1"
shift

echo "Creating multi-arch manifest: ${TARGET}"
docker buildx imagetools create -t "${TARGET}" "$@"
docker buildx imagetools inspect "${TARGET}"
