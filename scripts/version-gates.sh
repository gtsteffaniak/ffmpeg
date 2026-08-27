#!/bin/bash
# Version-aware dependency and configure gating for FFmpeg Docker builds.
# Shell conventions: needs_* returns 0 when the dependency IS required, 1 when it can be skipped.

ffmpeg_version_ge() {
  local ver=$1 min=$2
  local ver_key min_key

  ver_key=$(echo "$ver" | awk -F. '{printf "%04d%04d%04d", ($1==""?0:$1)+0, ($2==""?0:$2)+0, ($3==""?0:$3)+0}')
  min_key=$(echo "$min" | awk -F. '{printf "%04d%04d%04d", ($1==""?0:$1)+0, ($2==""?0:$2)+0, ($3==""?0:$3)+0}')

  [ "$ver_key" -ge "$min_key" ]
}

# libwebp is encode-only; skip on decode-only FFmpeg 9.0+ (native animated WebP decode).
needs_libwebp() {
  local ver=$1 decode_only=$2
  if [ "$decode_only" != "true" ]; then
    return 0
  fi
  if ffmpeg_version_ge "$ver" "9.0.0"; then
    return 1
  fi
  return 0
}

# OpenJPEG is encode-only in FFmpeg; native J2K decode is built-in.
needs_openjpeg() {
  local _ver=$1 decode_only=$2
  [ "$decode_only" != "true" ]
}

# libvpx wrappers are not needed for decode-only (native VP8/VP9 decoders).
needs_libvpx() {
  local _ver=$1 decode_only=$2
  [ "$decode_only" != "true" ]
}

# libaom decode wrapper optional when dav1d is present.
needs_libaom() {
  local _ver=$1 decode_only=$2
  [ "$decode_only" != "true" ]
}

# libvorbis wrapper not needed for decode-only (native Vorbis decoder).
needs_libvorbis() {
  local _ver=$1 decode_only=$2
  [ "$decode_only" != "true" ]
}
