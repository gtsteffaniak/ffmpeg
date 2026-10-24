#!/bin/bash
# Local hardware verification for full/static FFmpeg images or extracted binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${DIST:-${ROOT}/.local-build}"
IMAGE_FULL="${IMAGE_FULL:-gtstef/ffmpeg:local-full}"
IMAGE_STATIC="${IMAGE_STATIC:-gtstef/ffmpeg:local-static}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILED=1; }
FAILED=0

run_ffmpeg() {
  local variant=$1
  shift
  if [ "$variant" = "docker-full" ]; then
    docker run --rm --device /dev/dri:/dev/dri --group-add video \
      ${NVIDIA:+--gpus all} ${NVIDIA:+ -e NVIDIA_DRIVER_CAPABILITIES=video,compute,utility} \
      "$IMAGE_FULL" "$@"
  elif [ "$variant" = "docker-static" ]; then
    docker run --rm --device /dev/video11:/dev/video11 "$IMAGE_STATIC" "$@"
  else
    "$DIST/ffmpeg" "$@"
  fi
}

echo "=== hwtest (dist=${DIST}) ==="

if [ -e /dev/dri/renderD128 ]; then
  if run_ffmpeg docker-full -hide_banner -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -f lavfi -i testsrc=d=1:size=640x360 -c:v h264_vaapi -f null - 2>/dev/null; then
    pass "VAAPI h264_vaapi"
  else
    fail "VAAPI h264_vaapi"
  fi
else
  echo "SKIP: no /dev/dri/renderD128"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  NVIDIA=1
  if run_ffmpeg docker-full -hide_banner -f lavfi -i testsrc=d=1:size=640x360 -c:v h264_nvenc -f null - 2>/dev/null; then
    pass "NVENC h264_nvenc"
  else
    fail "NVENC h264_nvenc"
  fi
  unset NVIDIA
else
  echo "SKIP: no nvidia-smi"
fi

if [ "$(uname -m)" = "aarch64" ] && [ -e /dev/video11 ]; then
  if run_ffmpeg docker-static -hide_banner -f lavfi -i testsrc=d=1:size=640x360 \
    -c:v h264_v4l2m2m -f null - 2>/dev/null; then
    pass "v4l2m2m"
  else
    fail "v4l2m2m"
  fi
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "=== hwtest complete ==="
