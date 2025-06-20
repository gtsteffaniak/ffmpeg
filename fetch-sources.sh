#!/bin/bash

# Exit on error, undefined variable, or pipe failure
set -euo pipefail

# Create source directory if it doesn't exist and change into it
mkdir -p src && cd src
# Store the absolute path to the source directory
ROOT_DIR=$(pwd)

# Options for wget: retry on specific errors
WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 --timeout=60 --tries=3"
# Options for tar: extract, specify file, don't preserve owner
TAR_OPTS="--no-same-owner --extract --file"

fetch_and_unpack_git() {
  local name=$1
  local _unused_version_var=$2
  local url_var=$3
  local commit_var=${5:-}
  local _unused_strip_components=${6:-0}

  local url=""
  local commit=""

  [[ -n "$url_var" && ${!url_var+x} ]] && url="${!url_var}"
  [[ -n "$commit_var" && ${!commit_var+x} ]] && commit="${!commit_var}"

  if [[ -z "$url" ]]; then
    echo "Error: URL not set for $name"
    return 1
  fi

  for d in "$name"*; do
    [[ -d "$d" ]] && echo "Skipping $name, directory exists: $d" && return
  done

  echo "--- Cloning $name ---"
  git clone "$url" "$name"
  if [[ $? -ne 0 ]]; then
    echo "Git clone failed for $name"
    return 1
  fi

  if [[ -n "$commit" ]]; then
    echo "Checking out commit $commit"
    (cd "$name" && git checkout --recurse-submodules "$commit")
  fi

  echo "--- Cloned $name ---"
}
fetch_and_unpack() {
  local name=$1
  local version_var=$2
  local url_var=$3
  local _unused_commit_var=${5:-}
  local strip_components=${6:-0}

  local version=""
  local url=""
  local sha256=""

  [[ -n "$version_var" && ${!version_var+x} ]] && version="${!version_var}"
  [[ -n "$url_var" && ${!url_var+x} ]] && url="${!url_var}"

  if [[ -z "$url" ]]; then
    echo "Error: URL not set for $name"
    return 1
  fi

  local dir="${name}-${version}"

  if [[ -d "$dir" ]]; then
    echo "Skipping $name, directory exists: $dir"
    return
  fi

  echo "--- Downloading $name ---"
  local file="${name}.tar"
  wget -O "$file" "$url"

  if [[ -n "$sha256" ]]; then
    echo "$sha256  $file" | sha256sum -c -
  fi

  echo "--- Extracting to $dir ---"
  tar --no-same-owner --strip-components="$strip_components" -xf "$file"
  rm -f "$file"

  # Rename extracted dir to expected name
  for d in "$name"*; do
    if [[ -d "$d" && "$d" != "$dir" ]]; then
      mv "$d" "$dir"
      break
    fi
  done

  echo "--- Finished $dir ---"
}

: "${SVTAV1_VERSION:=3.0.2}"
: "${SVTAV1_URL:=https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.bz2}"
fetch_and_unpack SVT-AV1 SVTAV1_VERSION SVTAV1_URL

# --- Library Definitions and Fetching ---

# bump: ffmpeg /FFMPEG_VERSION=([\d.]+)/ https://github.com/FFmpeg/FFmpeg.git|*
# bump: ffmpeg after ./hashupdate Dockerfile FFMPEG $LATEST
# bump: ffmpeg link "Changelog" https://github.com/FFmpeg/FFmpeg/blob/n$LATEST/Changelog
# bump: ffmpeg link "Source diff $CURRENT..$LATEST" https://github.com/FFmpeg/FFmpeg/compare/n$CURRENT..n$LATEST
: "${FFMPEG_VERSION:=7.1.1}"
: "${FFMPEG_URL:=https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2}"
fetch_and_unpack ffmpeg FFMPEG_VERSION FFMPEG_URL

# bump: vorbis /VORBIS_VERSION=([\d.]+)/ https://github.com/xiph/vorbis.git|*
# bump: vorbis after ./hashupdate Dockerfile VORBIS $LATEST
# bump: vorbis link "CHANGES" https://github.com/xiph/vorbis/blob/master/CHANGES
# bump: vorbis link "Source diff $CURRENT..$LATEST" https://github.com/xiph/vorbis/compare/v$CURRENT..v$LATEST
: "${VORBIS_VERSION:=1.3.7}"
: "${VORBIS_URL:=https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz}"
fetch_and_unpack libvorbis VORBIS_VERSION VORBIS_URL

# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
: "${VPX_VERSION:=1.15.1}"
: "${VPX_URL:=https://github.com/webmproject/libvpx/archive/v${VPX_VERSION}.tar.gz}"
fetch_and_unpack libvpx VPX_VERSION VPX_URL

# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|^1
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
: "${LIBWEBP_VERSION:=1.5.0}"
: "${LIBWEBP_URL:=https://github.com/webmproject/libwebp/archive/v${LIBWEBP_VERSION}.tar.gz}"
fetch_and_unpack libwebp LIBWEBP_VERSION LIBWEBP_URL

# bump: libva /LIBVA_VERSION=([\d.]+)/ https://github.com/intel/libva.git|^2
# bump: libva after ./hashupdate Dockerfile LIBVA $LATEST
# bump: libva link "Changelog" https://github.com/intel/libva/blob/master/NEWS
: "${LIBVA_VERSION:=2.22.0}"
: "${LIBVA_URL:=https://github.com/intel/libva/archive/refs/tags/${LIBVA_VERSION}.tar.gz}"
fetch_and_unpack libva LIBVA_VERSION LIBVA_URL

# bump: srt /SRT_VERSION=([\d.]+)/ https://github.com/Haivision/srt.git|^1
# bump: srt after ./hashupdate Dockerfile SRT $LATEST
# bump: srt link "Release notes" https://github.com/Haivision/srt/releases/tag/v$LATEST
: "${SRT_VERSION:=1.5.4}"
: "${SRT_URL:=https://github.com/Haivision/srt/archive/v${SRT_VERSION}.tar.gz}"
fetch_and_unpack srt SRT_VERSION SRT_URL

# bump: ogg /OGG_VERSION=([\d.]+)/ https://github.com/xiph/ogg.git|*
# bump: ogg after ./hashupdate Dockerfile OGG $LATEST
# bump: ogg link "CHANGES" https://github.com/xiph/ogg/blob/master/CHANGES
# bump: ogg link "Source diff $CURRENT..$LATEST" https://github.com/xiph/ogg/compare/v$CURRENT..v$LATEST
#: "${OGG_VERSION:=1.3.5}"
#: "${OGG_URL:=https://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz}"
#: "${OGG_SHA256:=0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664}"
#fetch_and_unpack libogg OGG_VERSION OGG_URL OGG_SHA256


# bump: zimg /ZIMG_VERSION=([\d.]+)/ https://github.com/sekrit-twc/zimg.git|*
# bump: zimg after ./hashupdate Dockerfile ZIMG $LATEST
# bump: zimg link "ChangeLog" https://github.com/sekrit-twc/zimg/blob/master/ChangeLog
: "${ZIMG_VERSION:=3.0.5}"
: "${ZIMG_URL:=https://github.com/sekrit-twc/zimg/archive/release-${ZIMG_VERSION}.tar.gz}"
fetch_and_unpack zimg ZIMG_VERSION ZIMG_URL

# preferring rav1e-static rav1e-dev from apk (0.7.1)
# bump: rav1e /RAV1E_VERSION=([\d.]+)/ https://github.com/xiph/rav1e.git|/\d+\./|*
# bump: rav1e after ./hashupdate Dockerfile RAV1E $LATEST
# bump: rav1e link "Release notes" https://github.com/xiph/rav1e/releases/tag/v$LATEST
#: "${RAV1E_VERSION:=0.7.1}"
#: "${RAV1E_URL:=https://github.com/xiph/rav1e/archive/v${RAV1E_VERSION}.tar.gz}"
#: "${RAV1E_SHA256:=da7ae0df2b608e539de5d443c096e109442cdfa6c5e9b4014361211cf61d030c}"
#fetch_and_unpack rav1e RAV1E_VERSION RAV1E_URL RAV1E_SHA256

# bump: vorbis /VORBIS_VERSION=([\d.]+)/ https://github.com/xiph/vorbis.git|*
# bump: vorbis after ./hashupdate Dockerfile VORBIS $LATEST
# bump: vorbis link "CHANGES" https://github.com/xiph/vorbis/blob/master/CHANGES
# bump: vorbis link "Source diff $CURRENT..$LATEST" https://github.com/xiph/vorbis/compare/v$CURRENT..v$LATEST
: "${VORBIS_VERSION:=1.3.7}"
: "${VORBIS_URL:=https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz}"
fetch_and_unpack libvorbis VORBIS_VERSION VORBIS_URL

# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
: "${VPX_VERSION:=1.15.1}"
: "${VPX_URL:=https://github.com/webmproject/libvpx/archive/v${VPX_VERSION}.tar.gz}"
fetch_and_unpack libvpx VPX_VERSION VPX_URL

# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|^1
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
: "${LIBWEBP_VERSION:=1.5.0}"
: "${LIBWEBP_URL:=https://github.com/webmproject/libwebp/archive/v${LIBWEBP_VERSION}.tar.gz}"
fetch_and_unpack libwebp LIBWEBP_VERSION LIBWEBP_URL

# bump: librsvg /LIBRSVG_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/librsvg.git|^2
# bump: librsvg after ./hashupdate Dockerfile LIBRSVG $LATEST
# bump: librsvg link "NEWS" https://gitlab.gnome.org/GNOME/librsvg/-/blob/master/NEWS
: "${LIBRSVG_VERSION:=2.60.0}"
: "${LIBRSVG_URL:=https://download.gnome.org/sources/librsvg/2.60/librsvg-$LIBRSVG_VERSION.tar.xz}"
fetch_and_unpack librsvg LIBRSVG_VERSION LIBRSVG_URL

# bump: dav1d /DAV1D_VERSION=([\d.]+)/ https://code.videolan.org/videolan/dav1d.git|*
# bump: dav1d after ./hashupdate Dockerfile DAV1D $LATEST
# bump: dav1d link "Release notes" https://code.videolan.org/videolan/dav1d/-/tags/$LATEST
: "${DAV1D_VERSION:=1.5.1}"
: "${DAV1D_URL:=https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz}"
fetch_and_unpack dav1d DAV1D_VERSION DAV1D_URL

# preferring glib-static glib-dev from apk (2.84.1)
# own build as alpine glib links with libmount etc
# bump: glib /GLIB_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/glib.git|^2
# bump: glib after ./hashupdate Dockerfile GLIB $LATEST
# bump: glib link "NEWS" https://gitlab.gnome.org/GNOME/glib/-/blob/main/NEWS?ref_type=heads
#: "${GLIB_VERSION:=2.84.1}"
#: "${GLIB_URL:=https://download.gnome.org/sources/glib/2.84/glib-$GLIB_VERSION.tar.xz}"
#: "${GLIB_SHA256:=2b4bc2ec49611a5fc35f86aca855f2ed0196e69e53092bab6bb73396bf30789a}"
#fetch_and_unpack glib GLIB_VERSION GLIB_URL GLIB_SHA256

# bump: libbluray /LIBBLURAY_VERSION=([\d.]+)/ https://code.videolan.org/videolan/libbluray.git|*
# bump: libbluray after ./hashupdate Dockerfile LIBBLURAY $LATEST
# bump: libbluray link "ChangeLog" https://code.videolan.org/videolan/libbluray/-/blob/master/ChangeLog
: "${LIBBLURAY_VERSION:=1.3.4}"
: "${LIBBLURAY_URL:=https://code.videolan.org/videolan/libbluray/-/archive/$LIBBLURAY_VERSION/libbluray-$LIBBLURAY_VERSION.tar.gz}"
fetch_and_unpack libbluray LIBBLURAY_VERSION LIBBLURAY_URL

# bump: libvpl /LIBVPL_VERSION=([\d.]+)/ https://github.com/intel/libvpl.git|^2
# bump: libvpl after ./hashupdate Dockerfile LIBVPL $LATEST
# bump: libvpl link "Changelog" https://github.com/intel/libvpl/blob/main/CHANGELOG.md
: "${LIBVPL_VERSION:=2.14.0}"
: "${LIBVPL_URL:=https://github.com/intel/libvpl/archive/refs/tags/v${LIBVPL_VERSION}.tar.gz}"
fetch_and_unpack libvpl LIBVPL_VERSION LIBVPL_URL

# bump: libjxl /LIBJXL_VERSION=([\d.]+)/ https://github.com/libjxl/libjxl.git|^0
# bump: libjxl after ./hashupdate Dockerfile LIBJXL $LATEST
# bump: libjxl link "Changelog" https://github.com/libjxl/libjxl/blob/main/CHANGELOG.md
# use bundled highway library as its static build is not available in alpine
: "${LIBJXL_VERSION:=0.11.1}"
: "${LIBJXL_URL:=https://github.com/libjxl/libjxl/archive/refs/tags/v${LIBJXL_VERSION}.tar.gz}"
fetch_and_unpack libjxl LIBJXL_VERSION LIBJXL_URL


# bump: xevd /XEVD_VERSION=([\d.]+)/ https://github.com/mpeg5/xevd.git|*
# bump: xevd after ./hashupdate Dockerfile XEVD $LATEST
# bump: xevd link "CHANGELOG" https://github.com/mpeg5/xevd/releases/tag/v$LATEST
# TODO: better -DARM? possible to build on non arm and intel?
# TODO: report upstream about lib/libxevd.a?
: "${XEVD_VERSION:=0.5.0}"
: "${XEVD_URL:=https://github.com/mpeg5/xevd/archive/refs/tags/v$XEVD_VERSION.tar.gz}"
fetch_and_unpack xevd XEVD_VERSION XEVD_URL
# Custom step for xevd: create version.txt
if [[ -d "xevd-${XEVD_VERSION}" ]]; then
  echo "Running custom steps for xevd..."
  ( cd "xevd-${XEVD_VERSION}" && echo "v$XEVD_VERSION" > version.txt )
  echo "Finished custom steps for xevd."
else
    echo "Skipping custom steps for xevd (directory not found or skipped)."
fi

# bump: xeve /XEVE_VERSION=([\d.]+)/ https://github.com/mpeg5/xeve.git|*
# bump: xeve after ./hashupdate Dockerfile XEVE $LATEST
# bump: xeve link "CHANGELOG" https://github.com/mpeg5/xeve/releases/tag/v$LATEST
# TODO: better -DARM? possible to build on non arm and intel?
# TODO: report upstream about lib/libxeve.a?
: "${XEVE_VERSION:=0.5.1}"
: "${XEVE_URL:=https://github.com/mpeg5/xeve/archive/refs/tags/v$XEVE_VERSION.tar.gz}"
fetch_and_unpack xeve XEVE_VERSION XEVE_URL
# Custom step for xeve: create version.txt
if [[ -d "xeve-${XEVE_VERSION}" ]]; then
  echo "Running custom steps for xeve..."
  ( cd "xeve-${XEVE_VERSION}" && echo "v$XEVE_VERSION" > version.txt )
  echo "Finished custom steps for xeve."
else
    echo "Skipping custom steps for xeve (directory not found or skipped)."
fi

# Dropped
# bump: xavs2 /XAVS2_VERSION=([\d.]+)/ https://github.com/pkuvcl/xavs2.git|^1
# bump: xavs2 after ./hashupdate Dockerfile XAVS2 $LATEST
# bump: xavs2 link "Release" https://github.com/pkuvcl/xavs2/releases/tag/$LATEST
# bump: xavs2 link "Source diff $CURRENT..$LATEST" https://github.com/pkuvcl/xavs2/compare/v$CURRENT..v$LATEST
#XAVS2_VERSION=1.4
#XAVS2_URL="https://github.com/pkuvcl/xavs2/archive/refs/tags/$XAVS2_VERSION.tar.gz"
#: "${XAVS2_VERSION:=1.4}"
#: "${XAVS2_URL:=https://github.com/pkuvcl/xavs2/archive/refs/tags/$XAVS2_VERSION.tar.gz}"
#fetch_and_unpack xavs2 XAVS2_VERSION XAVS2_URL

# http://websvn.xvid.org/cvs/viewvc.cgi/trunk/xvidcore/build/generic/configure.in?revision=2146&view=markup
# bump: xvid /XVID_VERSION=([\d.]+)/ svn:https://anonymous:@svn.xvid.org|/^release-(.*)$/|/_/./|^1
# bump: xvid after ./hashupdate Dockerfile XVID $LATEST
# add extra CFLAGS that are not enabled by -O3
#: "${XVID_VERSION:=1.3.7}"
#: "${XVID_URL:=https://downloads.xvid.com/downloads/xvidcore-$XVID_VERSION.tar.gz}"
#: "${XVID_SHA256:=abbdcbd39555691dd1c9b4d08f0a031376a3b211652c0d8b3b8aa9be1303ce2d}"
## Use 'xvidcore' as name to match extracted directory
#fetch_and_unpack xvidcore XVID_VERSION XVID_URL XVID_SHA256

# bump: x265 /X265_VERSION=([\d.]+)/ https://bitbucket.org/multicoreware/x265_git.git|*
# bump: x265 after ./hashupdate Dockerfile X265 $LATEST
# bump: x265 link "Source diff $CURRENT..$LATEST" https://bitbucket.org/multicoreware/x265_git/branches/compare/$LATEST..$CURRENT#diff
: "${X265_VERSION:=4.0}"
: "${X265_URL:=https://bitbucket.org/multicoreware/x265_git/downloads/x265_$X265_VERSION.tar.gz}"
# NOTE: Original script saved this as .tar.bz2 and checked SHA against that name.
# The URL points to a .tar.gz file. Using the .tar.gz URL.
# The SHA provided might be for the .tar.bz2 and could fail verification against the .tar.gz.
# CMAKEFLAGS issue
# https://bitbucket.org/multicoreware/x265_git/issues/620/support-passing-cmake-flags-to-multilibsh
# Use 'x265' as name, function expects dir 'x265-${X265_VERSION}'
fetch_and_unpack x265 X265_VERSION X265_URL

# x264 only have a stable branch no tags and we checkout commit so no hash is needed
# bump: x264 /X264_VERSION=([[:xdigit:]]+)/ gitrefs:https://code.videolan.org/videolan/x264.git|re:#^refs/heads/stable$#|@commit
# bump: x264 after ./hashupdate Dockerfile X264 $LATEST
# bump: x264 link "Source diff $CURRENT..$LATEST" https://code.videolan.org/videolan/x264/-/compare/$CURRENT...$LATEST
: "${X264_URL:=https://code.videolan.org/videolan/x264.git}"
# Using commit hash as version identifier here for consistency, though not a tag/version
: "${X264_COMMIT:=31e19f92f00c7003fa115047ce50978bc98c3a0d}"
fetch_and_unpack_git x264 "" X264_URL "" X264_COMMIT

# bump: vid.stab /VIDSTAB_VERSION=([\d.]+)/ https://github.com/georgmartius/vid.stab.git|*
# bump: vid.stab after ./hashupdate Dockerfile VIDSTAB $LATEST
# bump: vid.stab link "Changelog" https://github.com/georgmartius/vid.stab/blob/master/Changelog
: "${VIDSTAB_VERSION:=1.1.1}"
: "${VIDSTAB_URL:=https://github.com/georgmartius/vid.stab/archive/v$VIDSTAB_VERSION.tar.gz}"
# Use 'vid.stab' as name, function expects dir 'vid.stab-${VIDSTAB_VERSION}'
fetch_and_unpack vid.stab VIDSTAB_VERSION VIDSTAB_URL

# bump: uavs3d /UAVS3D_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/uavs3/uavs3d.git|re:#^refs/heads/master$#|@commit
# bump: uavs3d after ./hashupdate Dockerfile UAVS3D $LATEST
# bump: uavs3d link "Source diff $CURRENT..$LATEST" https://github.com/uavs3/uavs3d/compare/$CURRENT..$LATEST
: "${UAVS3D_URL:=https://github.com/uavs3/uavs3d.git}"
: "${UAVS3D_COMMIT:=1fd04917cff50fac72ae23e45f82ca6fd9130bd8}"
# Removes BIT_DEPTH 10 to be able to build on other platforms. 10 was overkill anyways. (This comment refers to build steps, not fetch)
fetch_and_unpack_git uavs3d "" UAVS3D_URL "" UAVS3D_COMMIT

# bump: twolame /TWOLAME_VERSION=([\d.]+)/ https://github.com/njh/twolame.git|*
# bump: twolame after ./hashupdate Dockerfile TWOLAME $LATEST
# bump: twolame link "Source diff $CURRENT..$LATEST" https://github.com/njh/twolame/compare/v$CURRENT..v$LATEST
: "${TWOLAME_VERSION:=0.4.0}"
: "${TWOLAME_URL:=https://github.com/njh/twolame/releases/download/$TWOLAME_VERSION/twolame-$TWOLAME_VERSION.tar.gz}"
fetch_and_unpack twolame TWOLAME_VERSION TWOLAME_URL

# bump: theora /THEORA_VERSION=([\d.]+)/ https://github.com/xiph/theora.git|*
# bump: theora after ./hashupdate Dockerfile THEORA $LATEST
# bump: theora link "Release notes" https://github.com/xiph/theora/releases/tag/v$LATEST
# bump: theora link "Source diff $CURRENT..$LATEST" https://github.com/xiph/theora/compare/v$CURRENT..v$LATEST
#: "${THEORA_VERSION:=1.2.0}"
#: "${THEORA_URL:=http://downloads.xiph.org/releases/theora/libtheora-$THEORA_VERSION.tar.gz}"
## NOTE: Original script saved this as .tar.bz2. URL is .tar.gz. Using .tar.gz URL.
## Provided SHA might be for the .tar.bz2 and could fail verification.
## Use 'libtheora' as name to match extracted directory
#fetch_and_unpack libtheora THEORA_VERSION THEORA_URL

# bump: libshine /LIBSHINE_VERSION=([\d.]+)/ https://github.com/toots/shine.git|*
# bump: libshine after ./hashupdate Dockerfile LIBSHINE $LATEST
# bump: libshine link "CHANGELOG" https://github.com/toots/shine/blob/master/ChangeLog
# bump: libshine link "Source diff $CURRENT..$LATEST" https://github.com/toots/shine/compare/$CURRENT..$LATEST
: "${LIBSHINE_VERSION:=3.1.1}"
: "${LIBSHINE_URL:=https://github.com/toots/shine/releases/download/$LIBSHINE_VERSION/shine-$LIBSHINE_VERSION.tar.gz}"
# Use 'shine' as name to match extracted directory
fetch_and_unpack shine LIBSHINE_VERSION LIBSHINE_URL

# bump: rubberband /RUBBERBAND_VERSION=([\d.]+)/ https://github.com/breakfastquay/rubberband.git|^2
# bump: rubberband after ./hashupdate Dockerfile RUBBERBAND $LATEST
# bump: rubberband link "CHANGELOG" https://github.com/breakfastquay/rubberband/blob/default/CHANGELOG
# bump: rubberband link "Source diff $CURRENT..$LATEST" https://github.com/breakfastquay/rubberband/compare/$CURRENT..$LATEST
: "${RUBBERBAND_VERSION:=2.0.2}"
: "${RUBBERBAND_URL:=https://breakfastquay.com/files/releases/rubberband-$RUBBERBAND_VERSION.tar.bz2}"
fetch_and_unpack rubberband RUBBERBAND_VERSION RUBBERBAND_URL

# bump: openjpeg /OPENJPEG_VERSION=([\d.]+)/ https://github.com/uclouvain/openjpeg.git|*
# bump: openjpeg after ./hashupdate Dockerfile OPENJPEG $LATEST
# bump: openjpeg link "CHANGELOG" https://github.com/uclouvain/openjpeg/blob/master/CHANGELOG.md
: "${OPENJPEG_VERSION:=2.5.3}"
: "${OPENJPEG_URL:=https://github.com/uclouvain/openjpeg/archive/v$OPENJPEG_VERSION.tar.gz}"
fetch_and_unpack openjpeg OPENJPEG_VERSION OPENJPEG_URL

# bump: lcms2 /LCMS2_VERSION=([\d.]+)/ https://github.com/mm2/Little-CMS.git|^2
# bump: lcms2 after ./hashupdate Dockerfile LCMS2 $LATEST
# bump: lcms2 link "Release" https://github.com/mm2/Little-CMS/releases/tag/lcms$LATEST
: "${LCMS2_VERSION:=2.17}"
: "${LCMS2_URL:=https://github.com/mm2/Little-CMS/releases/download/lcms$LCMS2_VERSION/lcms2-$LCMS2_VERSION.tar.gz}"
fetch_and_unpack lcms2 LCMS2_VERSION LCMS2_URL

# bump: mp3lame /MP3LAME_VERSION=([\d.]+)/ svn:http://svn.code.sf.net/p/lame/svn|/^RELEASE__(.*)$/|/_/./|*
# bump: mp3lame after ./hashupdate Dockerfile MP3LAME $LATEST
# bump: mp3lame link "ChangeLog" http://svn.code.sf.net/p/lame/svn/trunk/lame/ChangeLog
: "${MP3LAME_VERSION:=3.100}"
: "${MP3LAME_URL:=https://sourceforge.net/projects/lame/files/lame/$MP3LAME_VERSION/lame-$MP3LAME_VERSION.tar.gz/download}"
# Use 'lame' as name to match extracted directory
fetch_and_unpack lame MP3LAME_VERSION MP3LAME_URL

# bump: libgsm /LIBGSM_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/timothytylee/libgsm.git|re:#^refs/heads/master$#|@commit
# bump: libgsm after ./hashupdate Dockerfile LIBGSM $LATEST
# bump: libgsm link "Changelog" https://github.com/timothytylee/libgsm/blob/master/ChangeLog
: "${LIBGSM_URL:=https://github.com/timothytylee/libgsm.git}"
: "${LIBGSM_COMMIT:=98f1708fb5e06a0dfebd58a3b40d610823db9715}"
fetch_and_unpack_git libgsm "" LIBGSM_URL "" LIBGSM_COMMIT

# bump: davs2 /DAVS2_VERSION=([\d.]+)/ https://github.com/pkuvcl/davs2.git|^1
# bump: davs2 after ./hashupdate Dockerfile DAVS2 $LATEST
# bump: davs2 link "Release" https://github.com/pkuvcl/davs2/releases/tag/$LATEST
# bump: davs2 link "Source diff $CURRENT..$LATEST" https://github.com/pkuvcl/davs2/compare/v$CURRENT..v$LATEST
: "${DAVS2_VERSION:=1.7}"
: "${DAVS2_URL:=https://github.com/pkuvcl/davs2/archive/refs/tags/$DAVS2_VERSION.tar.gz}"
fetch_and_unpack davs2 DAVS2_VERSION DAVS2_URL

# build after libvmaf
# bump: aom /AOM_VERSION=([\d.]+)/ git:https://aomedia.googlesource.com/aom|*
# bump: aom after ./hashupdate Dockerfile AOM $LATEST
# bump: aom after COMMIT=$(git ls-remote https://aomedia.googlesource.com/aom v$LATEST^{} | awk '{print $1}') && sed -i -E "s/^AOM_COMMIT=.*/AOM_COMMIT=$COMMIT/" Dockerfile
# bump: aom link "CHANGELOG" https://aomedia.googlesource.com/aom/+/refs/tags/v$LATEST/CHANGELOG
: "${AOM_VERSION:=3.12.1}"
: "${AOM_URL:=https://aomedia.googlesource.com/aom}"
: "${AOM_COMMIT:=10aece4157eb79315da205f39e19bf6ab3ee30d0}"
# NOTE: Using original git clone command because fetch_and_unpack doesn't support --depth 1 --branch
git clone --depth 1 --branch v$AOM_VERSION "$AOM_URL" && cd aom && test $(git rev-parse HEAD) = $AOM_COMMIT && cd $ROOT_DIR

# bump: harfbuzz /LIBHARFBUZZ_VERSION=([\d.]+)/ https://github.com/harfbuzz/harfbuzz.git|*
# bump: harfbuzz after ./hashupdate Dockerfile LIBHARFBUZZ $LATEST
# bump: harfbuzz link "NEWS" https://github.com/harfbuzz/harfbuzz/blob/main/NEWS
: "${LIBHARFBUZZ_VERSION:=11.2.0}"
: "${LIBHARFBUZZ_URL:=https://github.com/harfbuzz/harfbuzz/releases/download/$LIBHARFBUZZ_VERSION/harfbuzz-$LIBHARFBUZZ_VERSION.tar.xz}"
fetch_and_unpack harfbuzz LIBHARFBUZZ_VERSION LIBHARFBUZZ_URL


# bump: vmaf /VMAF_VERSION=([\d.]+)/ https://github.com/Netflix/vmaf.git|*
# bump: vmaf after ./hashupdate Dockerfile VMAF $LATEST
# bump: vmaf link "Release" https://github.com/Netflix/vmaf/releases/tag/v$LATEST
# bump: vmaf link "Source diff $CURRENT..$LATEST" https://github.com/Netflix/vmaf/compare/v$CURRENT..v$LATEST
: "${VMAF_VERSION:=3.0.0}"
: "${VMAF_URL:=https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz}"
fetch_and_unpack vmaf VMAF_VERSION VMAF_URL

# bump: vvenc /VVENC_VERSION=([\d.]+)/ https://github.com/fraunhoferhhi/vvenc.git|*
# bump: vvenc after ./hashupdate Dockerfile VVENC $LATEST
# bump: vvenc link "CHANGELOG" https://github.com/fraunhoferhhi/vvenc/releases/tag/v$LATEST
: "${VVENC_VERSION:=1.13.1}"
: "${VVENC_URL:=https://github.com/fraunhoferhhi/vvenc/archive/refs/tags/v$VVENC_VERSION.tar.gz}"
fetch_and_unpack vvenc VVENC_VERSION VVENC_URL

# bump: cairo /CAIRO_VERSION=([\d.]+)/ https://gitlab.freedesktop.org/cairo/cairo.git|^1
# bump: cairo after ./hashupdate Dockerfile CAIRO $LATEST
# bump: cairo link "NEWS" https://gitlab.freedesktop.org/cairo/cairo/-/blob/master/NEWS?ref_type=heads
: "${CAIRO_VERSION:=1.18.4}"
: "${CAIRO_URL:=https://cairographics.org/releases/cairo-$CAIRO_VERSION.tar.xz}"
fetch_and_unpack cairo CAIRO_VERSION CAIRO_URL

# TODO: there is weird "1.90" tag, skip it
# bump: pango /PANGO_VERSION=([\d.]+)/ https://github.com/GNOME/pango.git|/\d+\.\d+\.\d+/|*
# bump: pango after ./hashupdate Dockerfile PANGO $LATEST
# bump: pango link "NEWS" https://gitlab.gnome.org/GNOME/pango/-/blob/main/NEWS?ref_type=heads
: "${PANGO_VERSION:=1.56.3}"
: "${PANGO_URL:=https://download.gnome.org/sources/pango/1.56/pango-$PANGO_VERSION.tar.xz}"
# TODO: add -Dbuild-testsuite=false when in stable release
# TODO: -Ddefault_library=both currently to not fail building tests
fetch_and_unpack pango PANGO_VERSION PANGO_URL

# bump: libmysofa /LIBMYSOFA_VERSION=([\d.]+)/ https://github.com/hoene/libmysofa.git|^1
# bump: libmysofa after ./hashupdate Dockerfile LIBMYSOFA $LATEST
# bump: libmysofa link "Release" https://github.com/hoene/libmysofa/releases/tag/v$LATEST
# bump: libmysofa link "Source diff $CURRENT..$LATEST" https://github.com/hoene/libmysofa/compare/v$CURRENT..v$LATEST
: "${LIBMYSOFA_VERSION:=1.3.3}"
: "${LIBMYSOFA_URL:=https://github.com/hoene/libmysofa/archive/refs/tags/v$LIBMYSOFA_VERSION.tar.gz}"
fetch_and_unpack libmysofa LIBMYSOFA_VERSION LIBMYSOFA_URL

# bump: libass /LIBASS_VERSION=([\d.]+)/ https://github.com/libass/libass.git|*
# bump: libass after ./hashupdate Dockerfile LIBASS $LATEST
# bump: libass link "Release notes" https://github.com/libass/libass/releases/tag/$LATEST
: "${LIBASS_VERSION:=0.17.4}"
: "${LIBASS_URL:=https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz}"
fetch_and_unpack libass LIBASS_VERSION LIBASS_URL

echo "All fetching and unpacking complete."

# Optional: Return to the original directory if needed
# cd ..
