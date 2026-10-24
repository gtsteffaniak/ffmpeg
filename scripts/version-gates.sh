#!/bin/bash
# Version-aware dependency and configure gating for FFmpeg Docker builds.
# Shell conventions: needs_* returns 0 when the dependency IS required, 1 when it can be skipped.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=variant.sh
source "${SCRIPT_DIR}/variant.sh"

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

# libwebp is encode-only; native animated WebP decode exists on FFmpeg 9.0+ but we still
# ship libwebp for static/full software transcoding images.
needs_libwebp() {
  return 0
}

needs_openjpeg() {
  return 0
}

needs_libvpx() {
  local _ver=$1 _variant=$2
  [ "$(uname -m)" != "armv7l" ]
}

needs_libaom() {
  return 0
}

needs_libvorbis() {
  return 0
}

needs_libvpl_build() {
  normalize_build_variant
  [ "$BUILD_VARIANT" = "full" ] && ffmpeg_version_ge "$1" "6.0.0"
}

needs_vaapi_build() {
  normalize_build_variant
  [ "$BUILD_VARIANT" = "full" ]
}

needs_v4l2_m2m_build() {
  normalize_build_variant
  if [ "$BUILD_VARIANT" = "static" ]; then
    case "$(uname -m)" in
      aarch64|arm64) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 0
}

needs_modern_codecs_build() {
  local ver=$1 _variant=$2
  ffmpeg_version_ge "$ver" "7.0.0"
}

eval_fetch_gate() {
  local gate=$1
  local ffmpeg_version=$2
  local build_variant=$3
  export BUILD_VARIANT="${build_variant}"
  case "$gate" in
    always) return 0 ;;
    never) return 1 ;;
    decode_skip|static_skip) return 1 ;;
    needs_libwebp) needs_libwebp "$ffmpeg_version" "$build_variant" ;;
    needs_libvorbis) needs_libvorbis "$ffmpeg_version" "$build_variant" ;;
    needs_libvpx) needs_libvpx "$ffmpeg_version" "$build_variant" ;;
    needs_openjpeg) needs_openjpeg "$ffmpeg_version" "$build_variant" ;;
    needs_libaom) needs_libaom "$ffmpeg_version" "$build_variant" ;;
    needs_libvpl_build) needs_libvpl_build "$ffmpeg_version" ;;
    needs_vaapi_build) needs_vaapi_build ;;
    needs_v4l2_m2m_build) needs_v4l2_m2m_build ;;
    needs_modern_codecs_build) needs_modern_codecs_build "$ffmpeg_version" "$build_variant" ;;
    *)
      echo "Unknown fetch gate: $gate" >&2
      return 1
      ;;
  esac
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

_hw_flags_for_variant() {
  local configure=$1
  local ffmpeg_version=$2
  local build_variant=$3
  export BUILD_VARIANT="$build_variant"

  if [ "$build_variant" = "static" ]; then
    if needs_v4l2_m2m_build; then
      append_if_supported "$configure" BASE_FLAGS "--enable-v4l2-m2m"
    fi
    return
  fi

  local hw_flag
  for hw_flag in \
    --enable-vaapi \
    --enable-libvpl \
    --enable-ffnvcodec \
    --enable-nvenc \
    --enable-nvdec \
    --enable-cuvid \
    --enable-amf \
    --enable-vulkan \
    --enable-opencl; do
    append_if_supported "$configure" BASE_FLAGS "$hw_flag"
  done
  if needs_v4l2_m2m_build; then
    append_if_supported "$configure" BASE_FLAGS "--enable-v4l2-m2m"
  fi
}

# Populate BASE_FLAGS and FEATURES for Linux FFmpeg configure.
# Third argument: build variant (full | static).
build_ffmpeg_configure_flags() {
  local configure=${1:-./configure}
  local ffmpeg_version=$2
  local build_variant=${3:-full}
  export BUILD_VARIANT="$build_variant"

  BASE_FLAGS=""
  FEATURES=""

  append_if_supported "$configure" BASE_FLAGS "--disable-doc"

  _hw_flags_for_variant "$configure" "$ffmpeg_version" "$build_variant"

  local base_flag
  for base_flag in \
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

  if needs_libvpx "$ffmpeg_version" "$build_variant"; then
    append_if_supported "$configure" FEATURES "--enable-libvpx"
  fi
  if needs_libaom "$ffmpeg_version" "$build_variant"; then
    append_if_supported "$configure" FEATURES "--enable-libaom"
  fi
  if needs_openjpeg "$ffmpeg_version" "$build_variant"; then
    append_if_supported "$configure" FEATURES "--enable-libopenjpeg"
  fi
  if needs_libvorbis "$ffmpeg_version" "$build_variant"; then
    append_if_supported "$configure" FEATURES "--enable-libvorbis"
  fi
  if needs_libwebp "$ffmpeg_version" "$build_variant"; then
    append_if_supported "$configure" FEATURES "--enable-libwebp"
  fi

  local encode_flag
  for encode_flag in \
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

  # NVENC/AMF/cuvid require FFmpeg's nonfree flag; document in README/licensing.
  if [ "$build_variant" = "full" ]; then
    append_if_supported "$configure" FEATURES "--enable-nonfree"
  fi
}

build_windows_configure_flags() {
  local configure=${1:-./configure}
  local build_variant=${2:-static}

  BASE_FLAGS=""
  FEATURES=""

  local base_flag
  for base_flag in --enable-libdav1d --enable-libaom --enable-libvpx; do
    append_if_supported "$configure" BASE_FLAGS "$base_flag"
  done

  append_if_supported "$configure" BASE_FLAGS "--disable-doc"

  local encode_flag
  for encode_flag in --enable-libx264 --enable-libx265 --enable-libmp3lame; do
    append_if_supported "$configure" FEATURES "$encode_flag"
  done
}

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
