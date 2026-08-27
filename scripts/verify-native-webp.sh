#!/bin/sh
# Verify native animated WebP support on FFmpeg 9.0+ decode-only builds.
set -eu

. /tmp/version-gates.sh

if [ "${DECODE_ONLY:-false}" != "true" ] || ! ffmpeg_version_ge "${FFMPEG_VERSION:-0.0.0}" "9.0.0"; then
  echo "Skipping animated WebP test (FFmpeg ${FFMPEG_VERSION:-unknown}, DECODE_ONLY=${DECODE_ONLY:-false})"
  exit 0
fi

FFMPEG="${FFMPEG:-/usr/local/bin/ffmpeg}"
FFPROBE="${FFPROBE:-/usr/local/bin/ffprobe}"

"$FFMPEG" -hide_banner -demuxers 2>/dev/null | grep -q webp_anim

# Generate a tiny animated WebP and verify decode without libwebp.
apk add --no-cache libwebp-tools >/dev/null
"$FFMPEG" -y -f lavfi -i "color=c=red:s=16x16:d=0.1" -frames:v 1 /tmp/webp-test-1.png >/dev/null 2>&1
"$FFMPEG" -y -f lavfi -i "color=c=blue:s=16x16:d=0.1" -frames:v 1 /tmp/webp-test-2.png >/dev/null 2>&1
img2webp -o /tmp/anim-test.webp /tmp/webp-test-1.png /tmp/webp-test-2.png >/dev/null 2>&1

"$FFPROBE" -hide_banner /tmp/anim-test.webp 2>&1 | grep -q webp_anim
"$FFMPEG" -i /tmp/anim-test.webp -f null - >/dev/null 2>&1

echo "Animated WebP native decode OK"
