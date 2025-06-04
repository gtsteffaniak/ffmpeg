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
  local _unused_sha256_var=${4:-}
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
  local sha256_var=${4:-}
  local _unused_commit_var=${5:-}
  local strip_components=${6:-0}

  local version=""
  local url=""
  local sha256=""

  [[ -n "$version_var" && ${!version_var+x} ]] && version="${!version_var}"
  [[ -n "$url_var" && ${!url_var+x} ]] && url="${!url_var}"
  [[ -n "$sha256_var" && ${!sha256_var+x} ]] && sha256="${!sha256_var}"

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

: "${SVT-AV1_VERSION:=3.0.2}"
: "${SVT-AV1_URL:=https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v$SVTAV1_VERSION/SVT-AV1-v$SVTAV1_VERSION.tar.bz2}"
: "${SVT-AV1_SHA256:=7548a380cd58a46998ab4f1a02901ef72c37a7c6317c930cde5df2e6349e437b}"
fetch_and_unpack SVT-AV1 SVT-AV1_VERSION SVT-AV1_URL SVT-AV1_SHA256

# --- Library Definitions and Fetching ---

# bump: ffmpeg /FFMPEG_VERSION=([\d.]+)/ https://github.com/FFmpeg/FFmpeg.git|*
# bump: ffmpeg after ./hashupdate Dockerfile FFMPEG $LATEST
# bump: ffmpeg link "Changelog" https://github.com/FFmpeg/FFmpeg/blob/n$LATEST/Changelog
# bump: ffmpeg link "Source diff $CURRENT..$LATEST" https://github.com/FFmpeg/FFmpeg/compare/n$CURRENT..n$LATEST
: "${FFMPEG_VERSION:=7.1.1}"
: "${FFMPEG_URL:=https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2}"
: "${FFMPEG_SHA256:=0c8da2f11579a01e014fc007cbacf5bb4da1d06afd0b43c7f8097ec7c0f143ba}"
fetch_and_unpack ffmpeg FFMPEG_VERSION FFMPEG_URL FFMPEG_SHA256

# bump: vorbis /VORBIS_VERSION=([\d.]+)/ https://github.com/xiph/vorbis.git|*
# bump: vorbis after ./hashupdate Dockerfile VORBIS $LATEST
# bump: vorbis link "CHANGES" https://github.com/xiph/vorbis/blob/master/CHANGES
# bump: vorbis link "Source diff $CURRENT..$LATEST" https://github.com/xiph/vorbis/compare/v$CURRENT..v$LATEST
: "${VORBIS_VERSION:=1.3.7}"
: "${VORBIS_URL:=https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz}"
: "${VORBIS_SHA256:=0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab}"
fetch_and_unpack libvorbis VORBIS_VERSION VORBIS_URL VORBIS_SHA256

# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
: "${VPX_VERSION:=1.15.1}"
: "${VPX_URL:=https://github.com/webmproject/libvpx/archive/v${VPX_VERSION}.tar.gz}"
: "${VPX_SHA256:=6cba661b22a552bad729bd2b52df5f0d57d14b9789219d46d38f73c821d3a990}"
fetch_and_unpack libvpx VPX_VERSION VPX_URL VPX_SHA256

# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|^1
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
: "${LIBWEBP_VERSION:=1.5.0}"
: "${LIBWEBP_URL:=https://github.com/webmproject/libwebp/archive/v${LIBWEBP_VERSION}.tar.gz}"
: "${LIBWEBP_SHA256:=668c9aba45565e24c27e17f7aaf7060a399f7f31dba6c97a044e1feacb930f37}"
fetch_and_unpack libwebp LIBWEBP_VERSION LIBWEBP_URL LIBWEBP_SHA256

# bump: libva /LIBVA_VERSION=([\d.]+)/ https://github.com/intel/libva.git|^2
# bump: libva after ./hashupdate Dockerfile LIBVA $LATEST
# bump: libva link "Changelog" https://github.com/intel/libva/blob/master/NEWS
: "${LIBVA_VERSION:=2.22.0}"
: "${LIBVA_URL:=https://github.com/intel/libva/archive/refs/tags/${LIBVA_VERSION}.tar.gz}"
: "${LIBVA_SHA256:=467c418c2640a178c6baad5be2e00d569842123763b80507721ab87eb7af8735}"
fetch_and_unpack libva LIBVA_VERSION LIBVA_URL LIBVA_SHA256

# bump: srt /SRT_VERSION=([\d.]+)/ https://github.com/Haivision/srt.git|^1
# bump: srt after ./hashupdate Dockerfile SRT $LATEST
# bump: srt link "Release notes" https://github.com/Haivision/srt/releases/tag/v$LATEST
: "${SRT_VERSION:=1.5.4}"
: "${SRT_URL:=https://github.com/Haivision/srt/archive/v${SRT_VERSION}.tar.gz}"
: "${SRT_SHA256:=d0a8b600fe1b4eaaf6277530e3cfc8f15b8ce4035f16af4a5eb5d4b123640cdd}"
fetch_and_unpack srt SRT_VERSION SRT_URL SRT_SHA256

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
: "${ZIMG_SHA256:=a9a0226bf85e0d83c41a8ebe4e3e690e1348682f6a2a7838f1b8cbff1b799bcf}"
fetch_and_unpack zimg ZIMG_VERSION ZIMG_URL ZIMG_SHA256

# bump: libzmq /LIBZMQ_VERSION=([\d.]+)/ https://github.com/zeromq/libzmq.git|*
# bump: libzmq after ./hashupdate Dockerfile LIBZMQ $LATEST
# bump: libzmq link "NEWS" https://github.com/zeromq/libzmq/blob/master/NEWS
#: "${LIBZMQ_VERSION:=4.3.5}"
#: "${LIBZMQ_URL:=https://github.com/zeromq/libzmq/releases/download/v${LIBZMQ_VERSION}/zeromq-$#{LIBZMQ_VERSION}.tar.gz}"
#: "${LIBZMQ_SHA256:=6653ef5910f17954861fe72332e68b03ca6e4d9c7160eb3a8de5a5a913bfab43}"
#fetch_and_unpack zeromq LIBZMQ_VERSION LIBZMQ_URL LIBZMQ_SHA256

# bump: libgme /LIBGME_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/libgme/game-music-emu.git|re:#^refs/heads/master$#|@commit
# bump: libgme after ./hashupdate Dockerfile LIBGME $LATEST
# bump: libgme link "Source diff $CURRENT..$LATEST" https://github.com/libgme/game-music-emu/compare/$CURRENT..v$LATEST
: "${LIBGME_URL:=https://github.com/libgme/game-music-emu.git}"
: "${LIBGME_COMMIT:=9762cbcff3d2224ee0f8b8c41ec143e956ebad56}"
fetch_and_unpack_git game-music-emu "" LIBGME_URL "" LIBGME_COMMIT

# bump: libmodplug /LIBMODPLUG_VERSION=([\d.]+)/ fetch:https://sourceforge.net/projects/modplug-xmms/files/|/libmodplug-([\d.]+).tar.gz/
# bump: libmodplug after ./hashupdate Dockerfile LIBMODPLUG $LATEST
# bump: libmodplug link "NEWS" https://sourceforge.net/p/modplug-xmms/git/ci/master/tree/libmodplug/NEWS
#: "${LIBMODPLUG_VERSION:=0.8.9.0}"
#: "${LIBMODPLUG_URL:=https://downloads.sourceforge.net/modplug-xmms/libmodplug-${LIBMODPLUG_VERSION}.tar.gz}"
#: "${LIBMODPLUG_SHA256:=457ca5a6c179656d66c01505c0d95fafaead4329b9dbaa0f997d00a3508ad9de}"
#fetch_and_unpack libmodplug LIBMODPLUG_VERSION LIBMODPLUG_URL LIBMODPLUG_SHA256

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
: "${VORBIS_SHA256:=0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab}"
fetch_and_unpack libvorbis VORBIS_VERSION VORBIS_URL VORBIS_SHA256

# bump: libvpx /VPX_VERSION=([\d.]+)/ https://github.com/webmproject/libvpx.git|*
# bump: libvpx after ./hashupdate Dockerfile VPX $LATEST
# bump: libvpx link "CHANGELOG" https://github.com/webmproject/libvpx/blob/master/CHANGELOG
# bump: libvpx link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libvpx/compare/v$CURRENT..v$LATEST
: "${VPX_VERSION:=1.15.1}"
: "${VPX_URL:=https://github.com/webmproject/libvpx/archive/v${VPX_VERSION}.tar.gz}"
: "${VPX_SHA256:=6cba661b22a552bad729bd2b52df5f0d57d14b9789219d46d38f73c821d3a990}"
fetch_and_unpack libvpx VPX_VERSION VPX_URL VPX_SHA256

# bump: libwebp /LIBWEBP_VERSION=([\d.]+)/ https://github.com/webmproject/libwebp.git|^1
# bump: libwebp after ./hashupdate Dockerfile LIBWEBP $LATEST
# bump: libwebp link "Release notes" https://github.com/webmproject/libwebp/releases/tag/v$LATEST
# bump: libwebp link "Source diff $CURRENT..$LATEST" https://github.com/webmproject/libwebp/compare/v$CURRENT..v$LATEST
: "${LIBWEBP_VERSION:=1.5.0}"
: "${LIBWEBP_URL:=https://github.com/webmproject/libwebp/archive/v${LIBWEBP_VERSION}.tar.gz}"
: "${LIBWEBP_SHA256:=668c9aba45565e24c27e17f7aaf7060a399f7f31dba6c97a044e1feacb930f37}"
fetch_and_unpack libwebp LIBWEBP_VERSION LIBWEBP_URL LIBWEBP_SHA256

# bump: librsvg /LIBRSVG_VERSION=([\d.]+)/ https://gitlab.gnome.org/GNOME/librsvg.git|^2
# bump: librsvg after ./hashupdate Dockerfile LIBRSVG $LATEST
# bump: librsvg link "NEWS" https://gitlab.gnome.org/GNOME/librsvg/-/blob/master/NEWS
: "${LIBRSVG_VERSION:=2.60.0}"
: "${LIBRSVG_URL:=https://download.gnome.org/sources/librsvg/2.60/librsvg-$LIBRSVG_VERSION.tar.xz}"
: "${LIBRSVG_SHA256:=0b6ffccdf6e70afc9876882f5d2ce9ffcf2c713cbaaf1ad90170daa752e1eec3}"
fetch_and_unpack librsvg LIBRSVG_VERSION LIBRSVG_URL LIBRSVG_SHA256

# bump: dav1d /DAV1D_VERSION=([\d.]+)/ https://code.videolan.org/videolan/dav1d.git|*
# bump: dav1d after ./hashupdate Dockerfile DAV1D $LATEST
# bump: dav1d link "Release notes" https://code.videolan.org/videolan/dav1d/-/tags/$LATEST
: "${DAV1D_VERSION:=1.5.1}"
: "${DAV1D_URL:=https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz}"
: "${DAV1D_SHA256:=fa635e2bdb25147b1384007c83e15de44c589582bb3b9a53fc1579cb9d74b695}"
fetch_and_unpack dav1d DAV1D_VERSION DAV1D_URL DAV1D_SHA256

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
: "${LIBBLURAY_SHA256:=9820df5c3e87777be116ca225ad7ee026a3ff42b2447c7fe641910fb23aad3c2}"
: "${LIBUDFREAD_COMMIT:=a35513813819efadca82c4b90edbe1407b1b9e05}"
fetch_and_unpack libbluray LIBBLURAY_VERSION LIBBLURAY_URL LIBBLURAY_SHA256

# bump: libass /LIBASS_VERSION=([\d.]+)/ https://github.com/libass/libass.git|*
# bump: libass after ./hashupdate Dockerfile LIBASS $LATEST
# bump: libass link "Release notes" https://github.com/libass/libass/releases/tag/$LATEST
: "${LIBASS_VERSION:=0.17.3}"
: "${LIBASS_URL:=https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz}"
: "${LIBASS_SHA256:=da7c348deb6fa6c24507afab2dee7545ba5dd5bbf90a137bfe9e738f7df68537}"
fetch_and_unpack libass LIBASS_VERSION LIBASS_URL LIBASS_SHA256

# bump: kvazaar /KVAZAAR_VERSION=([\d.]+)/ https://github.com/ultravideo/kvazaar.git|^2
# bump: kvazaar after ./hashupdate Dockerfile KVAZAAR $LATEST
# bump: kvazaar link "Release notes" https://github.com/ultravideo/kvazaar/releases/tag/v$LATEST
: "${KVAZAAR_VERSION:=2.3.1}"
: "${KVAZAAR_URL:=https://github.com/ultravideo/kvazaar/archive/v$KVAZAAR_VERSION.tar.gz}"
: "${KVAZAAR_SHA256:=c5a1699d0bd50bc6bdba485b3438a5681a43d7b2c4fd6311a144740bfa59c9cc}"
fetch_and_unpack kvazaar KVAZAAR_VERSION KVAZAAR_URL KVAZAAR_SHA256

# bump: libvpl /LIBVPL_VERSION=([\d.]+)/ https://github.com/intel/libvpl.git|^2
# bump: libvpl after ./hashupdate Dockerfile LIBVPL $LATEST
# bump: libvpl link "Changelog" https://github.com/intel/libvpl/blob/main/CHANGELOG.md
: "${LIBVPL_VERSION:=2.14.0}"
: "${LIBVPL_URL:=https://github.com/intel/libvpl/archive/refs/tags/v${LIBVPL_VERSION}.tar.gz}"
: "${LIBVPL_SHA256:=7c6bff1c1708d910032c2e6c44998ffff3f5fdbf06b00972bc48bf2dd9e5ac06}"
fetch_and_unpack libvpl LIBVPL_VERSION LIBVPL_URL LIBVPL_SHA256

# bump: libjxl /LIBJXL_VERSION=([\d.]+)/ https://github.com/libjxl/libjxl.git|^0
# bump: libjxl after ./hashupdate Dockerfile LIBJXL $LATEST
# bump: libjxl link "Changelog" https://github.com/libjxl/libjxl/blob/main/CHANGELOG.md
# use bundled highway library as its static build is not available in alpine
: "${LIBJXL_VERSION:=0.11.1}"
: "${LIBJXL_URL:=https://github.com/libjxl/libjxl/archive/refs/tags/v${LIBJXL_VERSION}.tar.gz}"
: "${LIBJXL_SHA256:=1492dfef8dd6c3036446ac3b340005d92ab92f7d48ee3271b5dac1d36945d3d9}"
fetch_and_unpack libjxl LIBJXL_VERSION LIBJXL_URL LIBJXL_SHA256

# bump: xevd /XEVD_VERSION=([\d.]+)/ https://github.com/mpeg5/xevd.git|*
# bump: xevd after ./hashupdate Dockerfile XEVD $LATEST
# bump: xevd link "CHANGELOG" https://github.com/mpeg5/xevd/releases/tag/v$LATEST
# TODO: better -DARM? possible to build on non arm and intel?
# TODO: report upstream about lib/libxevd.a?
: "${XEVD_VERSION:=0.5.0}"
: "${XEVD_URL:=https://github.com/mpeg5/xevd/archive/refs/tags/v$XEVD_VERSION.tar.gz}"
: "${XEVD_SHA256:=8d55c7ec1a9ad4e70fe91fbe129a1d4dd288bce766f466cba07a29452b3cecd8}"
fetch_and_unpack xevd XEVD_VERSION XEVD_URL XEVD_SHA256
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
: "${XEVE_SHA256:=238c95ddd1a63105913d9354045eb329ad9002903a407b5cf1ab16bad324c245}"
fetch_and_unpack xeve XEVE_VERSION XEVE_URL XEVE_SHA256
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
#XAVS2_SHA256=1e6d731cd64cb2a8940a0a3fd24f9c2ac3bb39357d802432a47bc20bad52c6ce
#: "${XAVS2_VERSION:=1.4}"
#: "${XAVS2_URL:=https://github.com/pkuvcl/xavs2/archive/refs/tags/$XAVS2_VERSION.tar.gz}"
#: "${XAVS2_SHA256:=1e6d731cd64cb2a8940a0a3fd24f9c2ac3bb39357d802432a47bc20bad52c6ce}"
#fetch_and_unpack xavs2 XAVS2_VERSION XAVS2_URL XAVS2_SHA256

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
: "${X265_SHA256:=75b4d05629e365913de3100b38a459b04e2a217a8f30efaa91b572d8e6d71282}"
# CMAKEFLAGS issue
# https://bitbucket.org/multicoreware/x265_git/issues/620/support-passing-cmake-flags-to-multilibsh
# Use 'x265' as name, function expects dir 'x265-${X265_VERSION}'
fetch_and_unpack x265 X265_VERSION X265_URL X265_SHA256

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
: "${VIDSTAB_SHA256:=9001b6df73933555e56deac19a0f225aae152abbc0e97dc70034814a1943f3d4}"
# Use 'vid.stab' as name, function expects dir 'vid.stab-${VIDSTAB_VERSION}'
fetch_and_unpack vid.stab VIDSTAB_VERSION VIDSTAB_URL VIDSTAB_SHA256

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
: "${TWOLAME_SHA256:=cc35424f6019a88c6f52570b63e1baf50f62963a3eac52a03a800bb070d7c87d}"
fetch_and_unpack twolame TWOLAME_VERSION TWOLAME_URL TWOLAME_SHA256

# bump: theora /THEORA_VERSION=([\d.]+)/ https://github.com/xiph/theora.git|*
# bump: theora after ./hashupdate Dockerfile THEORA $LATEST
# bump: theora link "Release notes" https://github.com/xiph/theora/releases/tag/v$LATEST
# bump: theora link "Source diff $CURRENT..$LATEST" https://github.com/xiph/theora/compare/v$CURRENT..v$LATEST
#: "${THEORA_VERSION:=1.2.0}"
#: "${THEORA_URL:=http://downloads.xiph.org/releases/theora/libtheora-$THEORA_VERSION.tar.gz}"
## NOTE: Original script saved this as .tar.bz2. URL is .tar.gz. Using .tar.gz URL.
## Provided SHA might be for the .tar.bz2 and could fail verification.
#: "${THEORA_SHA256:=279327339903b544c28a92aeada7d0dcfd0397b59c2f368cc698ac56f515906e}"
## Use 'libtheora' as name to match extracted directory
#fetch_and_unpack libtheora THEORA_VERSION THEORA_URL THEORA_SHA256

# bump: libssh /LIBSSH_VERSION=([\d.]+)/ https://gitlab.com/libssh/libssh-mirror.git|*
# bump: libssh after ./hashupdate Dockerfile LIBSSH $LATEST
# bump: libssh link "Source diff $CURRENT..$LATEST" https://gitlab.com/libssh/libssh-mirror/-/compare/libssh-$CURRENT...libssh-$LATEST
# bump: libssh link "Release notes" https://gitlab.com/libssh/libssh-mirror/-/tags/libssh-$LATEST
: "${LIBSSH_VERSION:=0.11.1}"
: "${LIBSSH_URL:=https://gitlab.com/libssh/libssh-mirror/-/archive/libssh-$LIBSSH_VERSION/libssh-mirror-libssh-$LIBSSH_VERSION.tar.gz}"
: "${LIBSSH_SHA256:=b43ef9c91b6c3db64e7ba3db101eb89dbe645db63489c19d4f88cf6f84911ec6}"
# LIBSSH_STATIC=1 is REQUIRED to link statically against libssh.a so add to pkg-config file (Build step comment)
# Use 'libssh' as name, function expects dir 'libssh-${LIBSSH_VERSION}'
fetch_and_unpack libssh LIBSSH_VERSION LIBSSH_URL LIBSSH_SHA256

# bump: speex /SPEEX_VERSION=([\d.]+)/ https://github.com/xiph/speex.git|*
# bump: speex after ./hashupdate Dockerfile SPEEX $LATEST
# bump: speex link "ChangeLog" https://github.com/xiph/speex//blob/master/ChangeLog
# bump: speex link "Source diff $CURRENT..$LATEST" https://github.com/xiph/speex/compare/$CURRENT..$LATEST
: "${SPEEX_VERSION:=1.2.1}"
: "${SPEEX_URL:=https://github.com/xiph/speex/archive/Speex-$SPEEX_VERSION.tar.gz}"
: "${SPEEX_SHA256:=beaf2642e81a822eaade4d9ebf92e1678f301abfc74a29159c4e721ee70fdce0}"
fetch_and_unpack speex SPEEX_VERSION SPEEX_URL SPEEX_SHA256

# bump: libshine /LIBSHINE_VERSION=([\d.]+)/ https://github.com/toots/shine.git|*
# bump: libshine after ./hashupdate Dockerfile LIBSHINE $LATEST
# bump: libshine link "CHANGELOG" https://github.com/toots/shine/blob/master/ChangeLog
# bump: libshine link "Source diff $CURRENT..$LATEST" https://github.com/toots/shine/compare/$CURRENT..$LATEST
: "${LIBSHINE_VERSION:=3.1.1}"
: "${LIBSHINE_URL:=https://github.com/toots/shine/releases/download/$LIBSHINE_VERSION/shine-$LIBSHINE_VERSION.tar.gz}"
: "${LIBSHINE_SHA256:=58e61e70128cf73f88635db495bfc17f0dde3ce9c9ac070d505a0cd75b93d384}"
# Use 'shine' as name to match extracted directory
fetch_and_unpack shine LIBSHINE_VERSION LIBSHINE_URL LIBSHINE_SHA256

# bump: rubberband /RUBBERBAND_VERSION=([\d.]+)/ https://github.com/breakfastquay/rubberband.git|^2
# bump: rubberband after ./hashupdate Dockerfile RUBBERBAND $LATEST
# bump: rubberband link "CHANGELOG" https://github.com/breakfastquay/rubberband/blob/default/CHANGELOG
# bump: rubberband link "Source diff $CURRENT..$LATEST" https://github.com/breakfastquay/rubberband/compare/$CURRENT..$LATEST
: "${RUBBERBAND_VERSION:=2.0.2}"
: "${RUBBERBAND_URL:=https://breakfastquay.com/files/releases/rubberband-$RUBBERBAND_VERSION.tar.bz2}"
: "${RUBBERBAND_SHA256:=b9eac027e797789ae99611c9eaeaf1c3a44cc804f9c8a0441a0d1d26f3d6bdf9}"
fetch_and_unpack rubberband RUBBERBAND_VERSION RUBBERBAND_URL RUBBERBAND_SHA256

# bump: librtmp /LIBRTMP_COMMIT=([[:xdigit:]]+)/ gitrefs:https://git.ffmpeg.org/rtmpdump.git|re:#^refs/heads/master$#|@commit
# bump: librtmp after ./hashupdate Dockerfile LIBRTMP $LATEST
# bump: librtmp link "Commit diff $CURRENT..$LATEST" https://git.ffmpeg.org/gitweb/rtmpdump.git/commitdiff/$LATEST?ds=sidebyside
#: "${LIBRTMP_URL:=https://git.ffmpeg.org/rtmpdump.git}"
#: "${LIBRTMP_COMMIT:=6f6bb1353fc84f4cc37138baa99f586750028a01}"
## Use 'rtmpdump' as name to match cloned directory
#fetch_and_unpack_git rtmpdump "" LIBRTMP_URL "" LIBRTMP_COMMIT

# bump: librabbitmq /LIBRABBITMQ_VERSION=([\d.]+)/ https://github.com/alanxz/rabbitmq-c.git|*
# bump: librabbitmq after ./hashupdate Dockerfile LIBRABBITMQ $LATEST
# bump: librabbitmq link "ChangeLog" https://github.com/alanxz/rabbitmq-c/blob/master/ChangeLog.md
: "${LIBRABBITMQ_VERSION:=0.15.0}"
: "${LIBRABBITMQ_URL:=https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v$LIBRABBITMQ_VERSION.tar.gz}"
: "${LIBRABBITMQ_SHA256:=7b652df52c0de4d19ca36c798ed81378cba7a03a0f0c5d498881ae2d79b241c2}"
# Use 'rabbitmq-c' as name to match extracted directory
fetch_and_unpack rabbitmq-c LIBRABBITMQ_VERSION LIBRABBITMQ_URL LIBRABBITMQ_SHA256

# bump: opus /OPUS_VERSION=([\d.]+)/ https://github.com/xiph/opus.git|^1
# bump: opus after ./hashupdate Dockerfile OPUS $LATEST
# bump: opus link "Release notes" https://github.com/xiph/opus/releases/tag/v$LATEST
# bump: opus link "Source diff $CURRENT..$LATEST" https://github.com/xiph/opus/compare/v$CURRENT..v$LATEST
: "${OPUS_VERSION:=1.5.2}"
: "${OPUS_URL:=https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz}"
: "${OPUS_SHA256:=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1}"
fetch_and_unpack opus OPUS_VERSION OPUS_URL OPUS_SHA256

# bump: openjpeg /OPENJPEG_VERSION=([\d.]+)/ https://github.com/uclouvain/openjpeg.git|*
# bump: openjpeg after ./hashupdate Dockerfile OPENJPEG $LATEST
# bump: openjpeg link "CHANGELOG" https://github.com/uclouvain/openjpeg/blob/master/CHANGELOG.md
: "${OPENJPEG_VERSION:=2.5.3}"
: "${OPENJPEG_URL:=https://github.com/uclouvain/openjpeg/archive/v$OPENJPEG_VERSION.tar.gz}"
: "${OPENJPEG_SHA256:=368fe0468228e767433c9ebdea82ad9d801a3ad1e4234421f352c8b06e7aa707}"
fetch_and_unpack openjpeg OPENJPEG_VERSION OPENJPEG_URL OPENJPEG_SHA256

# bump: opencoreamr /OPENCOREAMR_VERSION=([\d.]+)/ fetch:https://sourceforge.net/projects/opencore-amr/files/opencore-amr/|/opencore-amr-([\d.]+).tar.gz/
# bump: opencoreamr after ./hashupdate Dockerfile OPENCOREAMR $LATEST
# bump: opencoreamr link "ChangeLog" https://sourceforge.net/p/opencore-amr/code/ci/master/tree/ChangeLog
: "${OPENCOREAMR_VERSION:=0.1.6}"
: "${OPENCOREAMR_URL:=https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-$OPENCOREAMR_VERSION.tar.gz}"
: "${OPENCOREAMR_SHA256:=483eb4061088e2b34b358e47540b5d495a96cd468e361050fae615b1809dc4a1}"
# Use 'opencore-amr' as name to match extracted directory
fetch_and_unpack opencore-amr OPENCOREAMR_VERSION OPENCOREAMR_URL OPENCOREAMR_SHA256

# bump: lcms2 /LCMS2_VERSION=([\d.]+)/ https://github.com/mm2/Little-CMS.git|^2
# bump: lcms2 after ./hashupdate Dockerfile LCMS2 $LATEST
# bump: lcms2 link "Release" https://github.com/mm2/Little-CMS/releases/tag/lcms$LATEST
: "${LCMS2_VERSION:=2.17}"
: "${LCMS2_URL:=https://github.com/mm2/Little-CMS/releases/download/lcms$LCMS2_VERSION/lcms2-$LCMS2_VERSION.tar.gz}"
: "${LCMS2_SHA256:=d11af569e42a1baa1650d20ad61d12e41af4fead4aa7964a01f93b08b53ab074}"
fetch_and_unpack lcms2 LCMS2_VERSION LCMS2_URL LCMS2_SHA256

# bump: mp3lame /MP3LAME_VERSION=([\d.]+)/ svn:http://svn.code.sf.net/p/lame/svn|/^RELEASE__(.*)$/|/_/./|*
# bump: mp3lame after ./hashupdate Dockerfile MP3LAME $LATEST
# bump: mp3lame link "ChangeLog" http://svn.code.sf.net/p/lame/svn/trunk/lame/ChangeLog
: "${MP3LAME_VERSION:=3.100}"
: "${MP3LAME_URL:=https://sourceforge.net/projects/lame/files/lame/$MP3LAME_VERSION/lame-$MP3LAME_VERSION.tar.gz/download}"
: "${MP3LAME_SHA256:=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e}"
# Use 'lame' as name to match extracted directory
fetch_and_unpack lame MP3LAME_VERSION MP3LAME_URL MP3LAME_SHA256

# bump: libgsm /LIBGSM_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/timothytylee/libgsm.git|re:#^refs/heads/master$#|@commit
# bump: libgsm after ./hashupdate Dockerfile LIBGSM $LATEST
# bump: libgsm link "Changelog" https://github.com/timothytylee/libgsm/blob/master/ChangeLog
: "${LIBGSM_URL:=https://github.com/timothytylee/libgsm.git}"
: "${LIBGSM_COMMIT:=98f1708fb5e06a0dfebd58a3b40d610823db9715}"
fetch_and_unpack_git libgsm "" LIBGSM_URL "" LIBGSM_COMMIT

# bump: fdk-aac /FDK_AAC_VERSION=([\d.]+)/ https://github.com/mstorsjo/fdk-aac.git|*
# bump: fdk-aac after ./hashupdate Dockerfile FDK_AAC $LATEST
# bump: fdk-aac link "ChangeLog" https://github.com/mstorsjo/fdk-aac/blob/master/ChangeLog
# bump: fdk-aac link "Source diff $CURRENT..$LATEST" https://github.com/mstorsjo/fdk-aac/compare/v$CURRENT..v$LATEST
: "${FDK_AAC_VERSION:=2.0.3}"
: "${FDK_AAC_URL:=https://github.com/mstorsjo/fdk-aac/archive/v$FDK_AAC_VERSION.tar.gz}"
: "${FDK_AAC_SHA256:=e25671cd96b10bad896aa42ab91a695a9e573395262baed4e4a2ff178d6a3a78}"
fetch_and_unpack fdk-aac FDK_AAC_VERSION FDK_AAC_URL FDK_AAC_SHA256

# bump: davs2 /DAVS2_VERSION=([\d.]+)/ https://github.com/pkuvcl/davs2.git|^1
# bump: davs2 after ./hashupdate Dockerfile DAVS2 $LATEST
# bump: davs2 link "Release" https://github.com/pkuvcl/davs2/releases/tag/$LATEST
# bump: davs2 link "Source diff $CURRENT..$LATEST" https://github.com/pkuvcl/davs2/compare/v$CURRENT..v$LATEST
: "${DAVS2_VERSION:=1.7}"
: "${DAVS2_URL:=https://github.com/pkuvcl/davs2/archive/refs/tags/$DAVS2_VERSION.tar.gz}"
: "${DAVS2_SHA256:=b697d0b376a1c7f7eda3a4cc6d29707c8154c4774358303653f0a9727f923cc8}"
fetch_and_unpack davs2 DAVS2_VERSION DAVS2_URL DAVS2_SHA256

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
: "${LIBHARFBUZZ_SHA256:=50f7d0a208367e606dbf6eecc5cfbecc01a47be6ee837ae7aff2787e24b09b45}"
fetch_and_unpack harfbuzz LIBHARFBUZZ_VERSION LIBHARFBUZZ_URL LIBHARFBUZZ_SHA256

# bump: vmaf /VMAF_VERSION=([\d.]+)/ https://github.com/Netflix/vmaf.git|*
# bump: vmaf after ./hashupdate Dockerfile VMAF $LATEST
# bump: vmaf link "Release" https://github.com/Netflix/vmaf/releases/tag/v$LATEST
# bump: vmaf link "Source diff $CURRENT..$LATEST" https://github.com/Netflix/vmaf/compare/v$CURRENT..v$LATEST
: "${VMAF_VERSION:=3.0.0}"
: "${VMAF_URL:=https://github.com/Netflix/vmaf/archive/refs/tags/v$VMAF_VERSION.tar.gz}"
: "${VMAF_SHA256:=7178c4833639e6b989ecae73131d02f70735fdb3fc2c7d84bc36c9c3461d93b1}"
fetch_and_unpack vmaf VMAF_VERSION VMAF_URL VMAF_SHA256

# bump: vvenc /VVENC_VERSION=([\d.]+)/ https://github.com/fraunhoferhhi/vvenc.git|*
# bump: vvenc after ./hashupdate Dockerfile VVENC $LATEST
# bump: vvenc link "CHANGELOG" https://github.com/fraunhoferhhi/vvenc/releases/tag/v$LATEST
: "${VVENC_VERSION:=1.13.1}"
: "${VVENC_URL:=https://github.com/fraunhoferhhi/vvenc/archive/refs/tags/v$VVENC_VERSION.tar.gz}"
: "${VVENC_SHA256:=9d0d88319b9c200ebf428471a3f042ea7dcd868e8be096c66e19120a671a0bc8}"
fetch_and_unpack vvenc VVENC_VERSION VVENC_URL VVENC_SHA256

# bump: cairo /CAIRO_VERSION=([\d.]+)/ https://gitlab.freedesktop.org/cairo/cairo.git|^1
# bump: cairo after ./hashupdate Dockerfile CAIRO $LATEST
# bump: cairo link "NEWS" https://gitlab.freedesktop.org/cairo/cairo/-/blob/master/NEWS?ref_type=heads
#: "${CAIRO_VERSION:=1.18.4}"
#: "${CAIRO_URL:=https://cairographics.org/releases/cairo-$CAIRO_VERSION.tar.xz}"
#: "${CAIRO_SHA256:=445ed8208a6e4823de1226a74ca319d3600e83f6369f99b14265006599c32ccb}"
#fetch_and_unpack cairo CAIRO_VERSION CAIRO_URL CAIRO_SHA256

# TODO: there is weird "1.90" tag, skip it
# bump: pango /PANGO_VERSION=([\d.]+)/ https://github.com/GNOME/pango.git|/\d+\.\d+\.\d+/|*
# bump: pango after ./hashupdate Dockerfile PANGO $LATEST
# bump: pango link "NEWS" https://gitlab.gnome.org/GNOME/pango/-/blob/main/NEWS?ref_type=heads
: "${PANGO_VERSION:=1.56.3}"
: "${PANGO_URL:=https://download.gnome.org/sources/pango/1.56/pango-$PANGO_VERSION.tar.xz}"
: "${PANGO_SHA256=2606252bc25cd8d24e1b7f7e92c3a272b37acd6734347b73b47a482834ba2491}"
# TODO: add -Dbuild-testsuite=false when in stable release
# TODO: -Ddefault_library=both currently to not fail building tests
fetch_and_unpack pango PANGO_VERSION PANGO_URL PANGO_SHA256

# bump: libmysofa /LIBMYSOFA_VERSION=([\d.]+)/ https://github.com/hoene/libmysofa.git|^1
# bump: libmysofa after ./hashupdate Dockerfile LIBMYSOFA $LATEST
# bump: libmysofa link "Release" https://github.com/hoene/libmysofa/releases/tag/v$LATEST
# bump: libmysofa link "Source diff $CURRENT..$LATEST" https://github.com/hoene/libmysofa/compare/v$CURRENT..v$LATEST
: "${LIBMYSOFA_VERSION:=1.3.3}"
: "${LIBMYSOFA_URL:=https://github.com/hoene/libmysofa/archive/refs/tags/v$LIBMYSOFA_VERSION.tar.gz}"
: "${LIBMYSOFA_SHA256=a15f7236a2b492f8d8da69f6c71b5bde1ef1bac0ef428b94dfca1cabcb24c84f}"
fetch_and_unpack libmysofa LIBMYSOFA_VERSION LIBMYSOFA_URL LIBMYSOFA_SHA256

echo "All fetching and unpacking complete."

# Optional: Return to the original directory if needed
# cd ..
