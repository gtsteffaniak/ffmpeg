#!/bin/bash
# Dependency catalog for release notes (versions from fetch-sources.sh, decode rules from version-gates.sh).
# Each entry: "Display Name|VERSION_VAR|COMMIT_VAR|src_glob|gate"
# gate: always | never | decode_skip | needs_libwebp | needs_libvorbis | needs_libvpx |
#       needs_openjpeg | needs_libaom | needs_libvpl_build | needs_modern_codecs_build

RELEASE_DEP_ROWS=(
  "FFmpeg|FFMPEG_VERSION||ffmpeg-*|always"
  "dav1d|DAV1D_VERSION||dav1d-*|always"
  "libaom|AOM_VERSION|AOM_COMMIT|aom|needs_libaom"
  "SVT-AV1|SVTAV1_VERSION||SVT-AV1-*|decode_skip"
  "rav1e|||__alpine__|decode_skip"
  "x264||X264_COMMIT|x264*|decode_skip"
  "x265|X265_VERSION||x265-*|decode_skip"
  "libvpx|VPX_VERSION||libvpx-*|needs_libvpx"
  "libwebp|LIBWEBP_VERSION||__alpine__|needs_libwebp"
  "openjpeg|OPENJPEG_VERSION||openjpeg-*|needs_openjpeg"
  "zimg|ZIMG_VERSION||zimg-*|always"
  "libvpl|LIBVPL_VERSION||libvpl-*|needs_libvpl_build"
  "xeve|XEVE_VERSION||xeve-*|needs_modern_codecs_build"
  "xevd|XEVD_VERSION||xevd-*|needs_modern_codecs_build"
  "vvenc|VVENC_VERSION||vvenc-*|needs_modern_codecs_build"
  "davs2|DAVS2_VERSION||davs2-*|decode_skip"
  "uavs3d|UAVS3D_VERSION|UAVS3D_COMMIT|uavs3d-*|decode_skip"
  "lame|MP3LAME_VERSION||lame-*|decode_skip"
  "rubberband|RUBBERBAND_VERSION||rubberband-*|decode_skip"
  "libvorbis|VORBIS_VERSION||__alpine__|needs_libvorbis"
  "opus|||__alpine__|always"
  "vo-amrwbenc|||__alpine__|decode_skip"
  "libass|LIBASS_VERSION||libass-*|always"
  "lcms2|LCMS2_VERSION||lcms2-*|always"
  "libmysofa|LIBMYSOFA_VERSION||libmysofa-*|decode_skip"
  "vmaf|VMAF_VERSION||vmaf-*|decode_skip"
  "vid.stab|VIDSTAB_VERSION||vid.stab-*|decode_skip"
  "harfbuzz|LIBHARFBUZZ_VERSION||__alpine__|always"
  "cairo|CAIRO_VERSION||__alpine__|decode_skip"
  "pango|PANGO_VERSION||pango-*|decode_skip"
  "libva|LIBVA_VERSION||__alpine__|always"
)

release_dep_in_decode() {
  local gate=$1
  local ffmpeg_version=$2

  case "$gate" in
    always) return 0 ;;
    never) return 1 ;;
    decode_skip) return 1 ;;
    needs_libwebp) needs_libwebp "$ffmpeg_version" "true" ;;
    needs_libvorbis) needs_libvorbis "$ffmpeg_version" "true" ;;
    needs_libvpx) needs_libvpx "$ffmpeg_version" "true" ;;
    needs_openjpeg) needs_openjpeg "$ffmpeg_version" "true" ;;
    needs_libaom) needs_libaom "$ffmpeg_version" "true" ;;
    needs_libvpl_build) needs_libvpl_build "$ffmpeg_version" ;;
    needs_modern_codecs_build) needs_modern_codecs_build "$ffmpeg_version" "true" ;;
    *)
      echo "Unknown release dep gate: $gate" >&2
      return 1
      ;;
  esac
}
