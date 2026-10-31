#!/bin/bash
# Build full glibc FFmpeg: codec libs static into the binary; libva/Vulkan/OpenCL dynamic.
# libvpl (dispatcher, dlopens the GPU runtime) and zimg are not packaged for bullseye, so they
# are built static from src/ like x264/x265/lame/SVT-AV1.
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:?FFMPEG_VERSION required}"

cd /build
. /tmp/version-gates.sh
# shellcheck source=scripts/debian-vulkan-build-deps.sh
. /tmp/debian-vulkan-build-deps.sh
install_debian_full_vulkan_build_deps

first_dir() {
  ls -d "$1" 2>/dev/null | head -n1
}

# nv-codec-headers for ffnvcodec / NVENC
if [ ! -d nv-codec-headers ]; then
  hdr=$(first_dir "nv-codec-headers*")
  if [ -n "$hdr" ]; then
    ln -sfn "$hdr" nv-codec-headers
  else
    git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git nv-codec-headers
  fi
fi
make -C nv-codec-headers install PREFIX=/usr/local

x264_dir=$(first_dir "x264*")
if [ -n "$x264_dir" ]; then
  cd "$x264_dir"
  ./configure --enable-pic --enable-static --disable-cli --disable-lavf --disable-swscale
  make -j"$(nproc)" install
  cd /build
fi

x265_dir=$(first_dir "x265*")
if [ -n "$x265_dir" ]; then
  cd "$x265_dir/build/linux"
  sed -i '/^cmake / s/$/ -G "Unix Makefiles" ${CMAKEFLAGS}/' ./multilib.sh
  sed -i 's/ -DENABLE_SHARED=OFF//g' ./multilib.sh
  MAKEFLAGS="-j$(nproc)" \
    CMAKEFLAGS="-DENABLE_SHARED=OFF -DCMAKE_VERBOSE_MAKEFILE=ON -DCMAKE_BUILD_TYPE=Release" \
    ./multilib.sh
  make -C 8bit -j"$(nproc)" install
  cd /build
fi

lame_dir=$(first_dir "lame*")
if [ -n "$lame_dir" ]; then
  cd "$lame_dir"
  ./configure --disable-shared --enable-static --enable-nasm --disable-gtktest --disable-cpml --disable-frontend
  make -j"$(nproc)" install
  cd /build
fi

svt_dir=$(first_dir "SVT-AV1*")
if [ -n "$svt_dir" ]; then
  cd "$svt_dir/Build"
  cmake .. -G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF
  make -j"$(nproc)" install
  cd /build
fi

zimg_dir=$(first_dir "zimg*")
if [ -n "$zimg_dir" ]; then
  cd "$zimg_dir"
  ./autogen.sh
  ./configure --prefix=/usr/local --disable-shared --enable-static --with-pic
  make -j"$(nproc)" install
  cd /build
fi

vpl_dir=$(first_dir "libvpl*")
if [ -n "$vpl_dir" ] && needs_libvpl_build "$FFMPEG_VERSION"; then
  cmake -S "$vpl_dir" -B "$vpl_dir/_build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DINSTALL_EXAMPLES=OFF \
    -DBUILD_TOOLS=OFF
  cmake --build "$vpl_dir/_build" -j"$(nproc)"
  cmake --install "$vpl_dir/_build"
fi

ff_dir=$(first_dir "ffmpeg*")
cd "$ff_dir"
apply_svtav1_api_patch
build_ffmpeg_configure_flags ./configure "$FFMPEG_VERSION" full

PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

./configure \
  --pkg-config-flags="--static" \
  --extra-cflags="${CFLAGS:-} -I/usr/local/include" \
  --extra-cxxflags="${CXXFLAGS:-} -I/usr/local/include" \
  --extra-ldflags="${LDFLAGS:-} -L/usr/local/lib -Wl,-Bstatic -lx264 -lx265 -lmp3lame -Wl,-Bdynamic -lva -lva-drm -ldl -lpthread" \
  --extra-libs="-lm -fopenmp -lstdc++" \
  --enable-small \
  --enable-gnutls \
  --disable-shared \
  --disable-ffplay \
  --enable-pic \
  --enable-gpl \
  --enable-version3 \
  $BASE_FLAGS \
  $FEATURES \
  || (cat ffbuild/config.log; false)

install_ffmpeg_progs
bundle_ffmpeg_doc /doc-bundle
