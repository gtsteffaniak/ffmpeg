#!/bin/bash
# Build-time Vulkan Video deps for full glibc FFmpeg on Debian bullseye (headers too old in distro).
set -euo pipefail

VULKAN_HEADERS_TAG="${VULKAN_HEADERS_TAG:-vulkan-sdk-1.4.341.0}"
SPIRV_HEADERS_TAG="${SPIRV_HEADERS_TAG:-vulkan-sdk-1.4.341.0}"

bookworm_apt_init() {
  if [ -f /etc/apt/sources.list.d/bookworm-vulkan.list ]; then
    return 0
  fi
  cat >/etc/apt/preferences.d/bookworm-vulkan <<'EOF'
Package: glslang-tools shaderc libshaderc-dev libvulkan-dev glslang-dev spirv-tools
Pin: release n=bookworm
Pin-Priority: 500
EOF
  echo 'deb http://deb.debian.org/debian bookworm main' >/etc/apt/sources.list.d/bookworm-vulkan.list
  apt-get update
}

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
}

install_shader_compiler() {
  bookworm_apt_init
  apt-get install -y --no-install-recommends -t bookworm \
    glslang-tools shaderc libvulkan-dev spirv-tools || \
    apt-get install -y --no-install-recommends -t bookworm glslang-tools
}

verify_vulkan_headers() {
  local hdr=/usr/local/include/vulkan/vulkan.h
  if [ ! -f "$hdr" ] && [ ! -f /usr/include/vulkan/vulkan.h ]; then
    echo "FAIL: Vulkan headers not installed" >&2
    exit 1
  fi
  if ! command -v glslc >/dev/null 2>&1 && ! command -v glslangValidator >/dev/null 2>&1; then
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
