#!/bin/bash
# Local hardware verification for full/static FFmpeg images or extracted binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${DIST:-${ROOT}/.local-build}"
IMAGE_FULL="${IMAGE_FULL:-gtstef/ffmpeg:local-full}"
IMAGE_STATIC="${IMAGE_STATIC:-gtstef/ffmpeg:local-static}"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILED=1; }
skip() { echo "SKIP: $*"; }
FAILED=0

wsl_env=()
wsl_mount=()
wsl_devices=()

if [ -e /dev/dxg ] && [ -d /usr/lib/wsl/lib ]; then
  wsl_env=(
    -e LIBVA_DRIVER_NAME=d3d12
    -e LIBVA_DRIVERS_PATH=/usr/lib/wsl/lib:/usr/lib/x86_64-linux-gnu/dri
    -e LD_LIBRARY_PATH=/usr/lib/wsl/lib
  )
  wsl_mount=(-v /usr/lib/wsl:/usr/lib/wsl:ro)
  wsl_devices=(--device /dev/dxg)
fi

run_ffmpeg() {
  local variant=$1
  shift
  if [ "$variant" = "docker-full" ]; then
    docker run --rm --device /dev/dri:/dev/dri --group-add video \
      ${NVIDIA:+--gpus all} \
      "$IMAGE_FULL" "$@"
  elif [ "$variant" = "docker-full-wsl" ]; then
    docker run --rm \
      "${wsl_devices[@]}" "${wsl_mount[@]}" "${wsl_env[@]}" \
      ${NVIDIA:+--gpus all} \
      "$IMAGE_FULL" "$@"
  elif [ "$variant" = "docker-static" ]; then
    docker run --rm --device /dev/video11:/dev/video11 "$IMAGE_STATIC" "$@"
  elif [ "$variant" = "local-full-wsl" ]; then
    env LIBVA_DRIVER_NAME=d3d12 \
      LIBVA_DRIVERS_PATH="/usr/lib/wsl/lib:${LIBVA_DRIVERS_PATH:-/usr/lib/x86_64-linux-gnu/dri}" \
      LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}" \
      "$DIST/ffmpeg" "$@"
  else
    "$DIST/ffmpeg" "$@"
  fi
}

echo "=== hwtest (dist=${DIST}) ==="

if [ -e /dev/dri/renderD128 ]; then
  if run_ffmpeg docker-full -hide_banner -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -f lavfi -i testsrc=d=1:size=640x360 -c:v h264_vaapi -f null - 2>/dev/null; then
    pass "VAAPI h264_vaapi (/dev/dri)"
  else
    fail "VAAPI h264_vaapi (/dev/dri)"
  fi

  if run_ffmpeg docker-full -hide_banner -init_hw_device vulkan=vk \
    -f lavfi -i testsrc=d=1:size=640x360 \
    -vf 'format=nv12,hwupload' -c:v h264_vulkan -f null - 2>/dev/null; then
    pass "Vulkan h264_vulkan (/dev/dri + Mesa/NVIDIA ICD)"
  else
    fail "Vulkan h264_vulkan (needs Vulkan ICD; NVIDIA also needs graphics capability)"
  fi
else
  skip "no /dev/dri/renderD128"
fi

if [ -e /dev/dxg ] && [ -d /usr/lib/wsl/lib ]; then
  echo "=== WSL2 GPU (/dev/dxg) ==="
  if run_ffmpeg docker-full-wsl -hide_banner -init_hw_device vaapi=va:/dev/dxg \
    -f lavfi -i testsrc=d=1:size=640x360 \
    -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null - 2>/dev/null; then
    pass "WSL VAAPI d3d12 h264_vaapi"
  else
    fail "WSL VAAPI d3d12 h264_vaapi"
  fi

  if [ -x "$DIST/ffmpeg" ]; then
    if run_ffmpeg local-full-wsl -hide_banner -init_hw_device vaapi=va:/dev/dxg \
      -f lavfi -i testsrc=d=1:size=320x240 -frames:v 1 -f null - 2>/dev/null; then
      pass "extracted binary VAAPI init on /dev/dxg"
    else
      fail "extracted binary VAAPI init on /dev/dxg"
    fi
  fi

  if docker info 2>/dev/null | grep -qi nvidia; then
    NVIDIA=1
    if run_ffmpeg docker-full-wsl -hide_banner -f lavfi -i testsrc=d=1:size=640x360 \
      -c:v h264_nvenc -f null - 2>/dev/null; then
      pass "WSL NVENC h264_nvenc (--gpus all + /usr/lib/wsl/lib)"
    else
      fail "WSL NVENC h264_nvenc"
    fi
    unset NVIDIA
  elif [ -e /usr/lib/wsl/lib/libcuda.so ] || [ -e /usr/lib/wsl/lib/libcuda.so.1 ]; then
    NVIDIA=1
    if run_ffmpeg docker-full-wsl -hide_banner -f lavfi -i testsrc=d=1:size=640x360 \
      -c:v h264_nvenc -f null - 2>/dev/null; then
      pass "WSL NVENC h264_nvenc (libcuda in /usr/lib/wsl/lib)"
    else
      fail "WSL NVENC h264_nvenc"
    fi
    unset NVIDIA
  else
    skip "WSL NVENC (no libcuda under /usr/lib/wsl/lib)"
  fi
else
  skip "WSL GPU (no /dev/dxg or /usr/lib/wsl/lib)"
fi

if command -v nvidia-smi >/dev/null 2>&1 && [ ! -e /dev/dxg ]; then
  NVIDIA=1
  if run_ffmpeg docker-full -hide_banner -f lavfi -i testsrc=d=1:size=640x360 -c:v h264_nvenc -f null - 2>/dev/null; then
    pass "NVENC h264_nvenc"
  else
    fail "NVENC h264_nvenc"
  fi
  unset NVIDIA
elif [ ! -e /dev/dxg ]; then
  skip "no nvidia-smi (native Linux NVENC)"
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
