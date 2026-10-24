#!/bin/bash
# Verify a static ffmpeg binary exposes filebrowser/go-ffmpeg software requirements.
set -euo pipefail

FFMPEG="${1:?ffmpeg path}"
FFPROBE="${2:-}"

require_encoder() {
  local name=$1
  "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -qE "(^|[[:space:]])${name}[[:space:]]" \
    || { echo "FAIL: missing encoder ${name}" >&2; exit 1; }
}

forbid_encoder() {
  local name=$1
  if "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -qE "(^|[[:space:]])${name}[[:space:]]"; then
    echo "FAIL: static must not include encoder ${name}" >&2
    exit 1
  fi
}

require_filter() {
  local name=$1
  "$FFMPEG" -hide_banner -filters 2>/dev/null | grep -qE "(^|[[:space:]])${name}[[:space:]]" \
    || { echo "FAIL: missing filter ${name}" >&2; exit 1; }
}

require_muxer() {
  local name=$1
  "$FFMPEG" -hide_banner -muxers 2>/dev/null | grep -qE "(^|[[:space:]])${name}[[:space:]]" \
    || { echo "FAIL: missing muxer ${name}" >&2; exit 1; }
}

require_demuxer() {
  local name=$1
  "$FFMPEG" -hide_banner -demuxers 2>/dev/null | grep -qE "(^|[[:space:]])${name}[[:space:]]" \
    || { echo "FAIL: missing demuxer ${name}" >&2; exit 1; }
}

require_protocol() {
  local name=$1
  "$FFMPEG" -hide_banner -protocols 2>/dev/null | grep -qw "$name" \
    || { echo "FAIL: missing protocol ${name}" >&2; exit 1; }
}

echo "=== filebrowser static capability check: ${FFMPEG} ==="

# Encoders (software paths only)
require_encoder libx264
require_encoder aac
require_encoder mjpeg

for enc in libx265 libx264rgb libsvtav1 librav1e libvpx libvvenc h264_nvenc h264_vaapi h264_qsv libwebp libopenjpeg; do
  forbid_encoder "$enc"
done

# Filters
for f in scale crop format transpose hflip vflip aresample fps segment concat tile; do
  require_filter "$f"
done

# Muxers / demuxers
for m in mp4 mpegts hls image2 segment; do
  require_muxer "$m"
done
require_muxer webvtt
require_demuxer concat

# Protocols
for p in file http https tcp rtsp; do
  require_protocol "$p"
done

if ! "$FFMPEG" -hide_banner -bsfs 2>/dev/null | grep -q aac_adtstoasc; then
  echo "FAIL: missing bitstream filter aac_adtstoasc" >&2
  exit 1
fi

if [ -n "$FFPROBE" ]; then
  "$FFPROBE" -version >/dev/null
fi

echo "=== filebrowser static capability check passed ==="
