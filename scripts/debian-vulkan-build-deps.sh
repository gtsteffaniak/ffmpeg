#!/bin/bash
# Build-time Vulkan Video deps for full glibc FFmpeg on Debian bullseye (headers too old in distro).
set -euo pipefail

VULKAN_HEADERS_TAG="${VULKAN_HEADERS_TAG:-vulkan-sdk-1.4.341.0}"
SPIRV_HEADERS_TAG="${SPIRV_HEADERS_TAG:-vulkan-sdk-1.4.341.0}"
GLSLANG_TAG="${GLSLANG_TAG:-vulkan-sdk-1.4.341.0}"

install_khronos_headers() {
  local work=/tmp/khronos-vulkan-build
  rm -rf "$work"
  mkdir -p "$work"
  cd "$work"

  git clone --depth 1 --branch "$VULKAN_HEADERS_TAG" \
    https://github.com/KhronosGroup/Vulkan-Headers.git
  cmake -S Vulkan-Headers -B vulkan-headers-build \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_BUILD_TYPE=Release
  cmake --install vulkan-headers-build

  git clone --depth 1 --branch "$SPIRV_HEADERS_TAG" \
    https://github.com/KhronosGroup/SPIRV-Headers.git
  cmake -S SPIRV-Headers -B spirv-headers-build \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_BUILD_TYPE=Release
  cmake --install spirv-headers-build
  cd /build
}

# FFmpeg 9 compiles Vulkan shaders at build time with glslc/glslang and needs SPIR-V 1.6
# (--target-env spirv1.6). bullseye glslang-tools 11.1 is too old, and pulling it from bookworm
# would upgrade libc6 in the builder and raise the glibc floor of the produced binary.
# Build glslang from source against the builder's own glibc instead (build-time tool only).
install_shader_compiler() {
  local work=/tmp/khronos-glslang-build
  rm -rf "$work"
  mkdir -p "$work"
  cd "$work"
  git clone --depth 1 --branch "$GLSLANG_TAG" https://github.com/KhronosGroup/glslang.git
  cmake -S glslang -B glslang-build \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_OPT=OFF \
    -DGLSLANG_TESTS=OFF \
    -DENABLE_GLSLANG_BINARIES=ON
  cmake --build glslang-build -j"$(nproc)"
  cmake --install glslang-build
  cd /build
}

verify_vulkan_headers() {
  local hdr=/usr/local/include/vulkan/vulkan.h
  if [ ! -f "$hdr" ] && [ ! -f /usr/include/vulkan/vulkan.h ]; then
    echo "FAIL: Vulkan headers not installed" >&2
    exit 1
  fi
  if ! command -v glslang >/dev/null 2>&1 && ! command -v glslangValidator >/dev/null 2>&1; then
    echo "FAIL: no glslc/glslangValidator for FFmpeg spirv_compiler" >&2
    exit 1
  fi
}

install_debian_full_vulkan_build_deps() {
  echo "=== Installing Vulkan Video build dependencies (full image) ==="
  apt-get update
  apt-get install -y --no-install-recommends git
  install_khronos_headers
  install_shader_compiler
  verify_vulkan_headers
  echo "=== Vulkan build dependencies OK ==="
}
