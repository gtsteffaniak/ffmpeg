#!/bin/bash
# Bookworm Mesa pieces on bullseye runtime: WSL d3d12 VA + Vulkan ICDs (RADV/ANV/lavapipe).
set -euo pipefail

DRI_DIR="/usr/lib/x86_64-linux-gnu/dri"

bookworm_apt_init() {
  if [ -f /etc/apt/sources.list.d/bookworm-mesa-gpu.list ]; then
    apt-get update
    return 0
  fi
  cat >/etc/apt/preferences.d/bookworm-mesa-gpu <<'EOF'
Package: mesa-va-drivers mesa-vulkan-drivers
Pin: release n=bookworm
Pin-Priority: 500
EOF
  echo 'deb http://deb.debian.org/debian bookworm main' >/etc/apt/sources.list.d/bookworm-mesa-gpu.list
  apt-get update
}

find_d3d12_driver() {
  find /usr/lib -name 'd3d12_drv_video.so' 2>/dev/null | head -n1
}

install_d3d12_from_deb() {
  local tmp
  tmp="$(mktemp -d)"
  cd "$tmp"
  apt-get download -t bookworm mesa-va-drivers
  dpkg-deb -x mesa-va-drivers_*.deb extract
  local src
  src="$(find extract -name 'd3d12_drv_video.so' | head -n1)"
  [ -n "$src" ] || return 1
  mkdir -p "$DRI_DIR"
  cp "$src" "$DRI_DIR/"
}

ensure_d3d12_va() {
  [ -n "$(find_d3d12_driver)" ] && return 0
  echo "Installing bookworm mesa-va-drivers for d3d12_drv_video.so"
  bookworm_apt_init
  if apt-get install -y --no-install-recommends -t bookworm mesa-va-drivers; then
    return 0
  fi
  echo "WARN: apt mesa-va-drivers failed; extracting d3d12 driver only"
  install_d3d12_from_deb
}

ensure_mesa_vulkan() {
  if [ -d /usr/share/vulkan/icd.d ] && [ -n "$(ls -A /usr/share/vulkan/icd.d 2>/dev/null)" ]; then
    if ls /usr/share/vulkan/icd.d/*radv* >/dev/null 2>&1 || \
       ls /usr/share/vulkan/icd.d/*intel* >/dev/null 2>&1 || \
       ls /usr/share/vulkan/icd.d/*lvp* >/dev/null 2>&1; then
      return 0
    fi
  fi
  echo "Installing bookworm mesa-vulkan-drivers for RADV/ANV/lavapipe ICDs"
  bookworm_apt_init
  apt-get install -y --no-install-recommends -t bookworm mesa-vulkan-drivers || \
    apt-get install -y --no-install-recommends mesa-vulkan-drivers
}

if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "Skipping bookworm Mesa GPU extras (not amd64)"
  exit 0
fi

ensure_d3d12_va
driver="$(find_d3d12_driver)"
[ -n "$driver" ] || { echo "FAIL: d3d12_drv_video.so missing" >&2; exit 1; }
echo "d3d12 VA driver: $driver"

ensure_mesa_vulkan
[ -d /usr/share/vulkan/icd.d ] && [ -n "$(ls -A /usr/share/vulkan/icd.d 2>/dev/null)" ] || \
  { echo "FAIL: no Vulkan ICD in /usr/share/vulkan/icd.d" >&2; exit 1; }
echo "Vulkan ICDs installed under /usr/share/vulkan/icd.d"
