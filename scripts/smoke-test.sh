#!/bin/bash
# Smoke-test a built ffmpeg image or binary (full glibc or static scratch).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/variant.sh
source "${SCRIPT_DIR}/variant.sh"

VARIANT="${1:-}"
IMAGE="${2:-}"
ARCH="${3:-}"

if [ -z "$VARIANT" ] || [ -z "$IMAGE" ]; then
  echo "Usage: $0 <full|static> <docker-image> [amd64|arm64]" >&2
  exit 1
fi

export BUILD_VARIANT="$VARIANT"
normalize_build_variant

PLATFORM=""
if [ -n "$ARCH" ]; then
  PLATFORM="linux/${ARCH}"
fi

docker_run_extra() {
  local extra=()
  if [ -n "$PLATFORM" ]; then
    extra+=(--platform "$PLATFORM")
  fi
  printf '%s\n' "${extra[@]}"
}

run_in_image() {
  # shellcheck disable=SC2046
  docker run --rm $(docker_run_extra) "$IMAGE" "$@"
}

run_in_image_sh() {
  # shellcheck disable=SC2046
  docker run --rm $(docker_run_extra) --entrypoint sh "$IMAGE" "$@"
}

echo "=== smoke-test variant=${VARIANT} image=${IMAGE} arch=${ARCH:-any} ==="

if command -v docker >/dev/null 2>&1; then
  img_bytes="$(docker image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null || echo 0)"
  if [ -n "$img_bytes" ] && [ "$img_bytes" != "0" ]; then
    echo "image_size_bytes:${img_bytes} (~$((img_bytes / 1024 / 1024)) MiB)"
  fi
fi

run_in_image ffmpeg -version
run_in_image ffprobe -version

hwaccels="$(run_in_image ffmpeg -hide_banner -hwaccels 2>/dev/null || true)"
echo "hwaccels:${hwaccels}"

if [ "$VARIANT" = "static" ]; then
  for token in vaapi cuda vulkan opencl qsv; do
    if echo "$hwaccels" | grep -qi "$token"; then
      echo "FAIL: static image lists GPU hwaccel: $token" >&2
      exit 1
    fi
  done
  if [ "$ARCH" = "arm64" ]; then
    echo "$hwaccels" | grep -qi v4l2m2m || echo "WARN: arm64 static missing v4l2m2m (optional without Pi headers)"
  fi
else
  for token in vaapi vulkan opencl drm; do
    echo "$hwaccels" | grep -qi "$token" || echo "WARN: full image missing hwaccel $token (configure/arch dependent)"
  done
fi

encoders="$(run_in_image ffmpeg -hide_banner -encoders 2>/dev/null)"
echo "$encoders" | grep -q libx264 || { echo "FAIL: missing libx264 encoder" >&2; exit 1; }

if [ "$VARIANT" = "full" ]; then
  for enc in h264_vaapi hevc_vaapi h264_nvenc h264_qsv h264_amf; do
    if ! echo "$encoders" | grep -q "$enc"; then
      echo "WARN: full image missing encoder $enc (may be arch/nonfree gated)"
    fi
  done
fi

echo "=== software encode (libx264) ==="
run_in_image ffmpeg -hide_banner -f lavfi -i testsrc=duration=1:size=320x240:rate=1 \
  -c:v libx264 -preset ultrafast -frames:v 5 -an -f null -

echo "=== init_hw_device graceful failure (no hardware) ==="
if [ "$VARIANT" = "full" ]; then
  run_in_image ffmpeg -hide_banner -init_hw_device vaapi=va:/dev/dri/renderD128 -f lavfi -i nullsrc -frames:v 1 -f null - \
    && echo "vaapi init unexpectedly succeeded" || echo "vaapi init failed gracefully (expected in CI)"
fi

if [ "$VARIANT" = "static" ]; then
  id=$(docker create ${PLATFORM:+--platform "$PLATFORM"} "$IMAGE")
  docker cp "$id:/ffmpeg" /tmp/ffmpeg-smoke-$$
  docker cp "$id:/ffprobe" /tmp/ffprobe-smoke-$$ 2>/dev/null || true
  docker rm -f "$id" >/dev/null
  "${SCRIPT_DIR}/checkelf.sh" "/tmp/ffmpeg-smoke-$$"
  "${SCRIPT_DIR}/check-filebrowser-static.sh" "/tmp/ffmpeg-smoke-$$" "/tmp/ffprobe-smoke-$$"
  rm -f "/tmp/ffmpeg-smoke-$$" "/tmp/ffprobe-smoke-$$"
  "${SCRIPT_DIR}/smoke-test-filebrowser.sh" "$IMAGE" "$ARCH"
else
  if [ "$ARCH" != "arm64" ]; then
    d3d12_drv="$(run_in_image_sh -c 'find /usr/lib -name d3d12_drv_video.so 2>/dev/null | head -1')"
    if [ -z "$d3d12_drv" ]; then
      echo "FAIL: full image missing d3d12_drv_video.so (WSL VAAPI)" >&2
      exit 1
    fi
    echo "OK: WSL VAAPI driver ${d3d12_drv}"
  fi
  id=$(docker create ${PLATFORM:+--platform "$PLATFORM"} "$IMAGE")
  docker cp "$id:/usr/local/bin/ffmpeg" /tmp/ffmpeg-smoke-$$
  docker rm -f "$id" >/dev/null
  "${SCRIPT_DIR}/checkldd.sh" "/tmp/ffmpeg-smoke-$$"
  rm -f "/tmp/ffmpeg-smoke-$$"
fi

echo "=== smoke-test passed ==="
