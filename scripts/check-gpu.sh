#!/bin/bash
# check-gpu.sh — verify a Track G (Debian GPU) image exposes GPU features.
#
# Usage:
#   ./scripts/check-gpu.sh [IMAGE]        # IMAGE defaults to gtstef/ffmpeg:9.0.2-gpu
#   IMAGE=gtstef/ffmpeg:9.0.2-gpu ./scripts/check-gpu.sh
#
# Runs against `docker run --rm <image>` (also works with a local
# binary if FFMPEG_BIN is set). Asserts, per brief:
#   ldd shows libva.so / libvpl.so / libvulkan.so
#   ffmpeg -hwaccels lists vaapi, cuda, vulkan (opencl where present)
#   ffmpeg -encoders lists h264_nvenc, h264_vaapi
#   ffmpeg -filters lists scale_vulkan, scale_vaapi
# Device smoke tests (VAAPI with /dev/dri, NVENC with --gpus all)
# are manual and documented in README.md — CI runners have no GPU.
set -euo pipefail

: "${IMAGE:=gtstef/ffmpeg:9.0.2-gpu}"
: "${FFMPEG_BIN:=}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
ok() { echo "OK: $*"; }

run_cmd() {
  if [ -n "$FFMPEG_BIN" ]; then
    "$FFMPEG_BIN" "$@"
  else
    docker run --rm "$IMAGE" "$@"
  fi
}

run_ldd() {
  if [ -n "$FFMPEG_BIN" ]; then
    ldd "$FFMPEG_BIN"
  else
    # ffmpeg is the entrypoint; exec a shell via entrypoint override.
    docker run --rm --entrypoint /bin/sh "$IMAGE" -c "ldd /usr/local/bin/ffmpeg"
  fi
}

command -v docker >/dev/null 2>&1 || { echo "docker required for check-gpu.sh" >&2; exit 1; }

echo "== Track G smoke: $IMAGE =="

run_cmd -version | head -3 || fail "ffmpeg -version failed"
ok "ffmpeg -version"

ldd_out="$(run_ldd)" || fail "ldd failed"
for lib in libva.so libvpl.so libvulkan.so; do
  echo "$ldd_out" | grep -q "$lib" || fail "ldd missing $lib"
done
ok "ldd shows libva/libvpl/libvulkan"

hw="$(run_cmd -hide_banner -hwaccels)" || fail "-hwaccels failed"
echo "$hw" | grep -q vaapi || fail "-hwaccels missing vaapi"
echo "$hw" | grep -q cuda || fail "-hwaccels missing cuda"
echo "$hw" | grep -q vulkan || fail "-hwaccels missing vulkan"
echo "$hw" | grep -q opencl || echo "NOTE: -hwaccels missing opencl (acceptable on some Mesa builds)"
ok "-hwaccels has vaapi/cuda/vulkan"

enc="$(run_cmd -hide_banner -encoders)" || fail "-encoders failed"
echo "$enc" | grep -q h264_nvenc || fail "-encoders missing h264_nvenc"
echo "$enc" | grep -q h264_vaapi || fail "-encoders missing h264_vaapi"
echo "$enc" | grep -q h264_vulkan || fail "-encoders missing h264_vulkan"
echo "$enc" | grep -q libx264 || fail "-encoders missing libx264 (codec parity)"
ok "-encoders has h264_nvenc/h264_vaapi/h264_vulkan/libx264"

filt="$(run_cmd -hide_banner -filters)" || fail "-filters failed"
echo "$filt" | grep -q scale_vulkan || fail "-filters missing scale_vulkan"
echo "$filt" | grep -q scale_vaapi || fail "-filters missing scale_vaapi"
ok "-filters has scale_vulkan/scale_vaapi"

echo "All Track G checks passed"
