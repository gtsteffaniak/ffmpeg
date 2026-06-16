#!/bin/bash
# Build Windows ffmpeg/ffprobe (components + final link, mirroring the Linux flow).
set -euo pipefail

DECODE_ONLY=${DECODE_ONLY:-false}
cd "$(dirname "$0")/.."

echo "Building Windows components (DECODE_ONLY=${DECODE_ONLY})"
DECODE_ONLY="${DECODE_ONLY}" COMPONENT=windows-components ./build.sh

echo "Building Windows final (DECODE_ONLY=${DECODE_ONLY})"
DECODE_ONLY="${DECODE_ONLY}" COMPONENT=windows ./build.sh
