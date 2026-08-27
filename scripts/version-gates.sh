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

configure_supports_flag() {
  local configure=$1 flag=$2
  "$configure" --help 2>/dev/null | grep -Fq -- "$flag"
}

append_if_supported() {
  local configure=$1 var_name=$2 flag=$3
  if configure_supports_flag "$configure" "$flag"; then
    eval "$var_name=\"\${$var_name} $flag\""
  fi
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

# libvpl (oneVPL) is only used by FFmpeg 6.0+.
needs_libvpl_build() {
  ffmpeg_version_ge "$1" "6.0.0"
}

# xeve/xevd/vvenc wrappers require FFmpeg 7.0+.
needs_modern_codecs_build() {
  local ver=$1 decode_only=$2
  [ "$decode_only" != "true" ] && ffmpeg_version_ge "$ver" "7.0.0"
}

# Evaluate a named fetch/release gate from sources.json.
# Returns 0 when the dependency should be included.
eval_fetch_gate() {
  local gate=$1
  local ffmpeg_version=$2
  local decode_only=$3
  case "$gate" in
    always) return 0 ;;
    never) return 1 ;;
    decode_skip) [ "$decode_only" != "true" ] ;;
    needs_libwebp) needs_libwebp "$ffmpeg_version" "$decode_only" ;;
    needs_libvorbis) needs_libvorbis "$ffmpeg_version" "$decode_only" ;;
    needs_libvpx) needs_libvpx "$ffmpeg_version" "$decode_only" ;;
    needs_openjpeg) needs_openjpeg "$ffmpeg_version" "$decode_only" ;;
    needs_libaom) needs_libaom "$ffmpeg_version" "$decode_only" ;;
    needs_libvpl_build) needs_libvpl_build "$ffmpeg_version" ;;
    needs_modern_codecs_build) needs_modern_codecs_build "$ffmpeg_version" "$decode_only" ;;
    *)
      echo "Unknown fetch gate: $gate" >&2
      return 1
      ;;
  esac
}

# Same gate names for release-table "In decode build" (decode_only forced true).
eval_release_gate() {
  eval_fetch_gate "$1" "$2" "true"
}

needs_svtav1_api_patch() {
  [ -f libavcodec/libsvtav1.c ] && \
    grep -q 'svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc,' libavcodec/libsvtav1.c
}

apply_svtav1_api_patch() {
  if needs_svtav1_api_patch; then
    sed -i 's/svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc, &svt_enc->enc_params)/svt_av1_enc_init_handle(\&svt_enc->svt_handle, \&svt_enc->enc_params)/g' libavcodec/libsvtav1.c
  fi
}

# Populate BASE_FLAGS and FEATURES for Linux static FFmpeg configure.
# Must be called from the ffmpeg source directory (or pass configure path).
build_ffmpeg_configure_flags() {
  local configure=${1:-./configure}
  local ffmpeg_version=$2
  local decode_only=$3

  BASE_FLAGS=""
  FEATURES=""

  append_if_supported "$configure" BASE_FLAGS "--disable-doc"

  local base_flag
  for base_flag in \
    --enable-libvpl \
    --enable-libzimg \
    --enable-fontconfig \
    --enable-gray \
    --enable-iconv \
    --enable-lcms2 \
    --enable-libxml2 \
    --enable-libdav1d \
    --enable-libass \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libharfbuzz \
    --enable-libsoxr \
    --enable-libsnappy; do
    append_if_supported "$configure" BASE_FLAGS "$base_flag"
  done

  if needs_libvpx "$ffmpeg_version" "$decode_only" && [ "$(uname -m)" != "armv7l" ]; then
    append_if_supported "$configure" FEATURES "--enable-libvpx"
  fi
  if needs_libaom "$ffmpeg_version" "$decode_only"; then
    append_if_supported "$configure" FEATURES "--enable-libaom"
  fi
  if needs_openjpeg "$ffmpeg_version" "$decode_only"; then
    append_if_supported "$configure" FEATURES "--enable-libopenjpeg"
  fi
  if needs_libvorbis "$ffmpeg_version" "$decode_only"; then
    append_if_supported "$configure" FEATURES "--enable-libvorbis"
  fi
  if needs_libwebp "$ffmpeg_version" "$decode_only"; then
    append_if_supported "$configure" FEATURES "--enable-libwebp"
  fi

  if [ "$decode_only" != "true" ]; then
    local encode_flag
    for encode_flag in \
      --enable-nonfree \
      --enable-libx264 \
      --enable-librav1e \
      --enable-libsvtav1 \
      --enable-libx265 \
      --enable-libxeve \
      --enable-libxevd \
      --enable-libvvenc \
      --enable-libdavs2 \
      --enable-libmysofa \
      --enable-libuavs3d \
      --enable-libvidstab \
      --enable-libvmaf \
      --enable-libvo-amrwbenc \
      --enable-libmp3lame; do
      append_if_supported "$configure" FEATURES "$encode_flag"
    done
  fi
}

# Populate BASE_FLAGS and FEATURES for Windows cross-compile configure.
build_windows_configure_flags() {
  local configure=${1:-./configure}
  local decode_only=$2

  BASE_FLAGS=""
  FEATURES=""

  local base_flag
  for base_flag in --enable-libdav1d --enable-libaom --enable-libvpx; do
    append_if_supported "$configure" BASE_FLAGS "$base_flag"
  done

  append_if_supported "$configure" BASE_FLAGS "--disable-doc"

  if [ "$decode_only" != "true" ]; then
    local encode_flag
    for encode_flag in --enable-nonfree --enable-libx264 --enable-libx265 --enable-libmp3lame; do
      append_if_supported "$configure" FEATURES "$encode_flag"
    done
  fi
}

# Install ffmpeg/ffprobe without building Texinfo HTML docs (legacy FFmpeg + Alpine texinfo).
install_ffmpeg_progs() {
  make -j"$(nproc)"
  if make -n install-progs >/dev/null 2>&1; then
    make -j"$(nproc)" install-progs
    if make -n install-data >/dev/null 2>&1; then
      make -j"$(nproc)" install-data
    fi
  else
    make -j"$(nproc)" install
  fi
}

bundle_ffmpeg_doc() {
  local out=${1:-/doc-bundle}
  mkdir -p "$out"
  if [ -d /usr/local/share/doc/ffmpeg ] && [ "$(ls -A /usr/local/share/doc/ffmpeg 2>/dev/null)" ]; then
    cp -a /usr/local/share/doc/ffmpeg/. "$out/"
  elif [ -d share/doc/ffmpeg ] && [ "$(ls -A share/doc/ffmpeg 2>/dev/null)" ]; then
    cp -a share/doc/ffmpeg/. "$out/"
  fi
  if [ -z "$(ls -A "$out" 2>/dev/null)" ]; then
    cp COPYING* "$out/" 2>/dev/null || true
  fi
}
