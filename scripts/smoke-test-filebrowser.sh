#!/bin/bash
# Exercise filebrowser-style ffmpeg commands on the static image/binary.
set -euo pipefail

IMAGE="${1:?docker image (static scratch)}"
ARCH="${2:-}"

PLATFORM=()
if [ -n "$ARCH" ]; then
  PLATFORM=(--platform "linux/${ARCH}")
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

run() {
  docker run --rm "${PLATFORM[@]}" -v "${WORKDIR}:/work" --entrypoint /ffmpeg "$IMAGE" "$@"
}

echo "=== filebrowser smoke: HLS fMP4 libx264+aac segment ==="
run -hide_banner -y \
  -f lavfi -i "testsrc=duration=2:size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:duration=2" \
  -map 0:v:0 -map 1:a:0 \
  -vf "format=yuv420p,scale=-2:min(360\\,ih)" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  -profile:v main -level 3.1 -tag:v avc1 \
  -g 60 -keyint_min 60 -sc_threshold 0 \
  -c:a aac -ar 48000 -ac 2 -profile:a aac_low \
  -af "aresample=async=1:first_pts=0" \
  -t 1.5 -video_track_timescale 90000 \
  -movflags empty_moov+frag_keyframe+default_base_moof \
  -f mp4 /work/seg.mp4

test -s "${WORKDIR}/seg.mp4"

echo "=== filebrowser smoke: video preview (mjpeg thumbnail) ==="
run -hide_banner -f lavfi -i "testsrc=duration=2:size=640x360:rate=30" \
  -vf "scale=min(320\\,iw):min(240\\,ih):force_original_aspect_ratio=decrease" \
  -frames:v 1 -q:v 3 -vcodec mjpeg -f image2 - | head -c 512 | grep -q .

echo "=== filebrowser smoke passed ==="
