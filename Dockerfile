ARG ALPINE_VERSION=alpine:3.22
FROM $ALPINE_VERSION AS builder

# Alpine Package Keeper options
ARG APK_OPTS="--no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/"

RUN apk add $APK_OPTS \
  coreutils \
  pkgconfig \
  rust cargo cargo-c \
  openssl-dev openssl-libs-static \
  ca-certificates \
  bash \
  git \
  curl \
  build-base \
  autoconf automake \
  libtool \
  diffutils \
  cmake meson ninja \
  yasm nasm \
  texinfo \
  jq \
  zlib-dev zlib-static \
  bzip2-dev bzip2-static \
  util-linux-dev util-linux-static \
  pixman-dev pixman-static \
  libxml2-dev libxml2-static \
  expat-dev expat-static \
  fontconfig-dev fontconfig-static \
  freetype freetype-dev freetype-static \
  graphite2-static \
  tiff tiff-dev \
  libjpeg-turbo libjpeg-turbo-dev \
  libpng-dev libpng-static \
  giflib giflib-dev \
  fribidi-dev fribidi-static \
  brotli-dev brotli-static \
  soxr-dev soxr-static \
  tcl \
  numactl-dev \
  cunit cunit-dev \
  fftw-dev \
  libsamplerate-dev libsamplerate-static \
  vo-amrwbenc-dev vo-amrwbenc-static \
  snappy snappy-dev snappy-static \
  xxd \
  xz-dev xz-static \
  python3 py3-packaging \
  libdrm-dev

# python3 py3-packaging needed by glib

# -O3 makes sure we compile with optimization. setting CFLAGS/CXXFLAGS seems to override
# default automake cflags.
# -static-libgcc is needed to make gcc not include gcc_s as "as-needed" shared library which
# cmake will include as a implicit library.
# other options to get hardened build (same as ffmpeg hardened)
ARG CFLAGS="-static-libgcc -fno-strict-overflow -fPIC"
ARG CXXFLAGS="-static-libgcc -fno-strict-overflow -fPIC"
ARG LDFLAGS="-Wl,-z,relro,-z,now"
# Add a DECODE_ONLY argument
ARG DECODE_ONLY="false" # Set "true" for decode-only, "false" for full build

RUN apk add $APK_OPTS glib-dev glib-static pcre2-dev pcre2-static

# Skip cairo, librsvg, pango if DECODE_ONLY is true (for smaller text rendering footprint if desired)
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping cairo build"; \
  else \
    apk add $APK_OPTS cairo-dev cairo-static; \
  fi

RUN apk add $APK_OPTS harfbuzz-dev harfbuzz-static

COPY [ "src/pango-*", "./pango" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
  echo "Skipping pango build"; \
else \
    apk add $APK_OPTS pango-dev pango; \
  fi

COPY [ "src/libva-*", "./libva" ]
# libva, vmaf is an analysis tool, likely not needed for pure decode unless for verification
RUN cd libva && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddisable_drm=false \
    -Dwith_x11=no \
    -Dwith_glx=no \
    -Dwith_wayland=no \
    -Dwith_win32=no \
    -Dwith_legacy=[] \
    -Denable_docs=false && \
  ninja -j$(nproc) -vC build install

COPY [ "src/vmaf-*", "./vmaf" ]
RUN cd vmaf/libvmaf && \
    meson setup build \
      -Dbuildtype=release \
      -Ddefault_library=static \
      -Dbuilt_in_models=true \
      -Denable_tests=false \
      -Denable_docs=false \
      -Denable_avx512=true \
      -Denable_float=true && \
    ninja -j$(nproc) -vC build install; \
    sed -i 's/-lvmaf /-lvmaf -lstdc++ /' /usr/local/lib/pkgconfig/libvmaf.pc;

# libbluray (niche)
COPY [ "src/libbluray-*", "./libbluray" ]
RUN if [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping libbluray build"; \
  else \
    # dec_init rename is to workaround https://code.videolan.org/videolan/libbluray/-/issues/43
    cd libbluray && \
    sed -i 's/dec_init/libbluray_dec_init/' src/libbluray/disc/* && \
    git clone https://code.videolan.org/videolan/libudfread.git contrib/libudfread && \
    (cd contrib/libudfread && git checkout --recurse-submodules $LIBUDFREAD_COMMIT) && \
    autoreconf -fiv && \
    ./configure \
      --with-pic \
      --disable-doxygen-doc \
      --disable-doxygen-dot \
      --enable-static \
      --disable-shared \
      --disable-examples \
      --disable-bdjava-jar && \
    make -j$(nproc) install; \
  fi

# aom (AV1 decoder)
RUN apk add $APK_OPTS aom-dev aom-static

# libogg (niche audio codec)
RUN apk add $APK_OPTS libogg-dev libogg-static

# davs2 (very niche)
COPY [ "src/davs2-*", "./davs2" ]
RUN if [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping davs2 build"; \
  else \
    # TODO: seems to be issues with asm on musl
    cd davs2/build/linux && \
    ./configure \
      --disable-asm \
      --enable-pic \
      --enable-strip \
      --disable-cli && \
    make -j$(nproc) install; \
  fi

# Remove lame (MP3 encoder)
COPY [ "src/lame-*", "./lame" ]
RUN if [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping lame build"; \
  else \
    cd lame && \
    ./configure \
      --disable-shared \
      --enable-static \
      --enable-nasm \
      --disable-gtktest \
      --disable-cpml \
      --disable-frontend && \
    make -j$(nproc) install; \
  fi

COPY [ "src/lcms2-*", "./lcms2" ]
RUN cd lcms2 && \
  ./autogen.sh && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) install

# Keep openjpeg (JPEG 2000 decoder)
COPY [ "src/openjpeg-*", "./openjpeg" ]
RUN cd openjpeg && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_PKGCONFIG_FILES=ON \
    -DBUILD_CODEC=OFF \
    -DWITH_ASTYLE=OFF \
    -DBUILD_TESTING=OFF \
    .. && \
  make -j$(nproc) install


# Remove rubberband (audio processing)
COPY [ "src/rubberband-*", "./rubberband" ]
RUN if [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping rubberband build"; \
  else \
    cd rubberband && \
    meson setup build \
      -Ddefault_library=static \
      -Dfft=fftw \
      -Dresampler=libsamplerate && \
    ninja -j$(nproc) -vC build install && \
    echo "Requires.private: fftw3 samplerate" >> /usr/local/lib/pkgconfig/rubberband.pc; \
  fi

# SVT-AV1 (AV1 encoder)
COPY [ "src/SVT-AV1-*", "./SVT-AV1" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping SVT-AV1 build"; \
  else \
    cd SVT-AV1 && \
    cd Build && \
    cmake \
      -G"Unix Makefiles" \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=OFF \
      -DENABLE_AVX512=ON \
      -DCMAKE_BUILD_TYPE=Release \
      .. && \
    make -j$(nproc) install; \
  fi

# uavs3d (AVS3 decoder - niche, already in your DECODE_ONLY section)
COPY [ "src/uavs3d*", "./uavs3d" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
  echo "Skipping uavs3d build"; \
  else \
    cd uavs3d && \
      sed -i '/armv7\.c/d' source/CMakeLists.txt && \
      mkdir -p build/linux && cd build/linux && \
      cmake \
        -G"Unix Makefiles" \
        -DCMAKE_VERBOSE_MAKEFILE=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        ../.. && \
      make -j$(nproc) install; \
  fi

# vid.stab (video processing)
COPY [ "src/vid.stab-*", "./vid.stab" ]
RUN if [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping vid.stab build"; \
  else \
    cd vid.stab && \
    mkdir build && cd build && \
    sed -i 's/include (FindSSE)/if(CMAKE_SYSTEM_ARCH MATCHES "amd64")\ninclude (FindSSE)\nendif()/' ../CMakeLists.txt && \
    cmake \
      -G"Unix Makefiles" \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      -DCMAKE_SYSTEM_ARCH=$(arch) \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DUSE_OMP=ON \
      .. && \
    make -j$(nproc) install; \
    echo "Libs.private: -ldl" >> /usr/local/lib/pkgconfig/vidstab.pc; \
  fi

# Remove x264 (encoder)
COPY [ "src/x264*", "./x264" ]
RUN if [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping x264 build"; \
  else \
    cd x264 && \
    ./configure \
      --enable-pic \
      --enable-static \
      --disable-cli \
      --disable-lavf \
      --disable-swscale && \
    make -j$(nproc) install; \
  fi

# x265 (HEVC encoder)
COPY [ "src/x265*", "./x265" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping x265 build"; \
  else \
    cd x265/build/linux && \
      sed -i '/^cmake / s/$/ -G "Unix Makefiles" ${CMAKEFLAGS}/' ./multilib.sh && \
      sed -i 's/ -DENABLE_SHARED=OFF//g' ./multilib.sh && \
      MAKEFLAGS="-j$(nproc)" \
      CMAKEFLAGS="-DENABLE_SHARED=OFF -DCMAKE_VERBOSE_MAKEFILE=ON -DENABLE_AGGRESSIVE_CHECKS=ON -DENABLE_NASM=ON -DCMAKE_BUILD_TYPE=Release" \
      ./multilib.sh && \
      make -C 8bit -j$(nproc) install; \
  fi

# xeve (HEVC encoder)
COPY [ "src/xeve-*", "./xeve" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
  echo "Skipping xeve build"; \
  else \
    cd xeve && \
    sed -i 's/mc_filter_bilin/xevem_mc_filter_bilin/' src_main/sse/xevem_mc_sse.c && \
    mkdir build && cd build && \
    cmake \
      -G"Unix Makefiles" \
      -DARM="$(if [ $(uname -m) == aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
      -DCMAKE_BUILD_TYPE=Release \
      .. && \
    make -j$(nproc) install && \
    ln -s /usr/local/lib/xeve/libxeve.a /usr/local/lib/libxeve.a; \
  fi

# xevd (VVC/H.266 encoder)
COPY [ "src/xevd-*", "./xevd" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
  echo "Skipping xevd build"; \
  else \
    cd xevd && \
    sed -i 's/mc_filter_bilin/xevdm_mc_filter_bilin/' src_main/sse/xevdm_mc_sse.c && \
    mkdir build && cd build && \
    cmake \
      -G"Unix Makefiles" \
      -DARM="$(if [ $(uname -m) == aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
      -DCMAKE_BUILD_TYPE=Release \
      .. && \
    make -j$(nproc) install && \
    ln -s /usr/local/lib/xevd/libxevd.a /usr/local/lib/libxevd.a; \
  fi

# libjxl (image codec)
COPY [ "src/libjxl-*", "./libjxl" ]
RUN if [ "$(uname -m)" = "armv7l" ]; then \
  echo "Skipping libjxl build"; \
  else \
    set -e && \
    cd libjxl && \
    ./deps.sh && \
    cmake -B build \
      -G"Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TESTING=OFF \
      -DJPEGXL_ENABLE_PLUGINS=OFF \
      -DJPEGXL_ENABLE_BENCHMARK=OFF \
      -DJPEGXL_ENABLE_COVERAGE=OFF \
      -DJPEGXL_ENABLE_EXAMPLES=OFF \
      -DJPEGXL_ENABLE_FUZZERS=OFF \
      -DJPEGXL_ENABLE_SJPEG=OFF \
      -DJPEGXL_ENABLE_SKCMS=OFF \
      -DJPEGXL_ENABLE_VIEWERS=OFF \
      -DJPEGXL_FORCE_SYSTEM_GTEST=ON \
      -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
      -DJPEGXL_FORCE_SYSTEM_HWY=OFF && \
    cmake --build build -j$(nproc) && \
    cmake --install build; \
  fi

# hardware acceleration for intel cpu
COPY [ "src/libvpl-*", "./libvpl" ]
RUN cd libvpl && \
    cmake -B build \
      -G"Unix Makefiles" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TESTS=OFF \
      -DENABLE_WARNING_AS_ERROR=ON && \
    cmake --build build -j$(nproc) && \
    cmake --install build;

# vvenc (HEVC encoder)
COPY [ "src/vvenc-*", "./vvenc" ]
RUN if [ "$(uname -m)" = "armv7l" ] || [ "$DECODE_ONLY" = "true" ]; then \
    echo "Skipping vvenc build"; \
    else \
    cd vvenc && \
      sed -i 's/-Werror;//' source/Lib/vvenc/CMakeLists.txt && \
      cmake \
        -S . \
        -B build/release-static \
        -DVVENC_ENABLE_WERROR=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local && \
      cmake --build build/release-static -j && \
      cmake --build build/release-static --target install; \
    fi

# dav1d (AV1 decoder)
COPY [ "src/dav1d-*", "./dav1d" ]
RUN cd dav1d && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

# rav1e (AV1 encoder)
RUN apk add $APK_OPTS rav1e-static rav1e-dev

# Keep zimg (image processing for decode, scaling etc.)
COPY [ "src/zimg-*", "./zimg" ]
RUN cd zimg && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

# libwebp (decoder)
RUN apk add $APK_OPTS libwebp-dev libwebp-static

# libvpx (VP8/VP9 decoder)
COPY [ "src/libvpx-*", "./libvpx" ]
RUN if [ "$(uname -m)" = "armv7l" ]; then \
  echo "DECODE_ONLY is true, skipping libvpx build"; \
  else \
    cd libvpx && \
    ./configure \
      --enable-static \
      --enable-vp9-highbitdepth \
      --disable-shared \
      --disable-unit-tests \
      --disable-examples && \
    make -j$(nproc) install; \
  fi

# libvorbis (decoder)
RUN apk add $APK_OPTS libvorbis-dev libvorbis-static

COPY [ "src/libass-*", "./libass" ]
RUN cd libass && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) && make install

COPY [ "src/libmysofa-*", "./libmysofa" ]
RUN cd libmysofa/build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    .. && \
  make -j$(nproc) install

COPY [ "src/ffmpeg*", "./ffmpeg" ]
RUN cd ffmpeg && \
  sed -i 's/svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc, &svt_enc->enc_params)/svt_av1_enc_init_handle(\&svt_enc->svt_handle, \&svt_enc->enc_params)/g' libavcodec/libsvtav1.c && \
  if [ "$(uname -m)" != "armv7l" ]; then \
    FEATURES="--enable-libvpx"; \
  fi; \
  # Conditional flags based on DECODE_ONLY
  if [ "$DECODE_ONLY" != "true" ]; then \
    FEATURES="$FEATURES --enable-nonfree"; \
    FEATURES="$FEATURES --enable-libx264"; \
    FEATURES="$FEATURES --enable-librav1e"; \
    FEATURES="$FEATURES --enable-libsvtav1"; \
    FEATURES="$FEATURES --enable-libx265"; \
    FEATURES="$FEATURES --enable-libxeve"; \
    FEATURES="$FEATURES --enable-libxevd"; \
    FEATURES="$FEATURES --enable-libvvenc"; \
    FEATURES="$FEATURES --enable-libbluray"; \
    FEATURES="$FEATURES --enable-libdavs2"; \
    # For the GSM audio codec, used in telephony.
    #FEATURES="$FEATURES --enable-libgsm"; \
    # 3d audio support.
    FEATURES="$FEATURES --enable-libmysofa"; \
    # AMR audio codecs for mobile.
    # High-quality audio pitch shifting.
    #FEATURES="$FEATURES --enable-librubberband"; \
    # libmp3lame is superior and already included.
    #FEATURES="$FEATURES --enable-libshine"; \
    #FEATURES="$FEATURES --enable-libtheora"; \
    #FEATURES="$FEATURES --enable-libtwolame"; \
    FEATURES="$FEATURES --enable-libuavs3d"; \
    # Video stabilization filter.
    FEATURES="$FEATURES --enable-libvidstab"; \
    FEATURES="$FEATURES --enable-libvmaf"; \
    FEATURES="$FEATURES --enable-libvo-amrwbenc"; \
    #FEATURES="$FEATURES --enable-libjxl"; \
    #FEATURES="$FEATURES --enable-librsvg"; \
    FEATURES="$FEATURES --enable-libmp3lame"; \
    #FEATURES="$FEATURES --enable-libshine"; \
  fi && \
    PKG_CONFIG_PATH="/usr/lib/pkgconfig/:${PKG_CONFIG_PATH}" && \
    ./configure \
    --pkg-config-flags="--static" \
    --extra-cflags="$CFLAGS" \
    --extra-cxxflags="$CXXFLAGS" \
    --extra-ldexeflags="-fPIE -static-pie" \
    --extra-libs="-lm -fopenmp" \
    --enable-small \
    #--enable-vulkan \
    --enable-openssl \
    --disable-shared \
    --disable-ffplay \
    --enable-static \
    --enable-gpl \
    --enable-libvpl \
    --enable-libvorbis \
    --enable-version3 \
    --enable-libzimg \
    --enable-fontconfig \
    --enable-gray \
    --enable-iconv \
    --enable-lcms2 \
    --enable-libaom \
    --enable-libwebp \
    --enable-libxml2 \
    --enable-libdav1d \
    --enable-libass \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libharfbuzz \
    --enable-libsoxr \
    --enable-libopenjpeg \
    --enable-libsnappy \
    $FEATURES \
  || (cat ffbuild/config.log ; false) && \
  make -j$(nproc) install

# make sure binaries has no dependencies, is relro, pie and stack nx
COPY checkelf /
RUN \
  /checkelf /usr/local/bin/ffmpeg && \
  /checkelf /usr/local/bin/ffprobe

# workaround for using -Wl,--allow-multiple-definition
# see comment in checkdupsym for details
COPY checkdupsym /
RUN /checkdupsym /ffmpeg-*

# some basic fonts that don't take up much space
RUN apk add $APK_OPTS font-terminus font-inconsolata font-dejavu font-awesome

FROM scratch AS testing
COPY --from=builder /usr/local/bin/ffmpeg /
COPY --from=builder /usr/local/bin/ffprobe /
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/

# sanity tests
RUN ["/ffmpeg", "-version"]
RUN ["/ffprobe", "-version"]
RUN ["/ffmpeg", "-hide_banner", "-buildconf"]
# stack size
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libsvtav1", "-t", "100ms", "-f", "null", "-"]
# dns
RUN ["/ffprobe", "-i", "https://github.com/favicon.ico"]
# tls/https certs
RUN ["/ffprobe", "-tls_verify", "1", "-ca_file", "/etc/ssl/cert.pem", "-i", "https://github.com/favicon.ico"]
# svg
RUN ["/ffprobe", "-i", "https://github.githubassets.com/favicons/favicon.svg"]
# vvenc
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libvvenc", "-t", "100ms", "-f", "null", "-"]
# x265 regression
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libx265", "-t", "100ms", "-f", "null", "-"]

FROM scratch
COPY --from=builder /usr/local/bin/ffmpeg /
COPY --from=builder /usr/local/bin/ffprobe /
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/

ENTRYPOINT ["/ffmpeg"]
