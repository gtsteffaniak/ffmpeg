#!/bin/bash
# Ensure Mesa ships the WSL2 VAAPI driver (d3d12_drv_video.so) in the full image.
# Bullseye's mesa-va-drivers is too old; use bookworm mesa on amd64 when missing.
set -euo pipefail

DRI_DIR="/usr/lib/x86_64-linux-gnu/dri"

find_d3d12_driver() {
  find /usr/lib -name 'd3d12_drv_video.so' 2>/dev/null | head -n1
}

install_from_bookworm_deb() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  cd "$tmp"
  apt-get download -t bookworm mesa-va-drivers
  dpkg-deb -x mesa-va-drivers_*.deb extract
  local src
  src="$(find extract -name 'd3d12_drv_video.so' | head -n1)"
  if [ -z "$src" ]; then
    return 1
  fi
  mkdir -p "$DRI_DIR"
  cp "$src" "$DRI_DIR/"
}

if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "Skipping d3d12 VA driver install (not amd64)"
  exit 0
fi

if [ -n "$(find_d3d12_driver)" ]; then
  echo "d3d12 VA driver already present: $(find_d3d12_driver)"
  exit 0
fi

echo "d3d12_drv_video.so not found after base mesa-va-drivers; fetching bookworm Mesa"

cat >/etc/apt/preferences.d/mesa-bookworm <<'EOF'
Package: mesa-va-drivers
Pin: release n=bookworm
Pin-Priority: 500
EOF

echo 'deb http://deb.debian.org/debian bookworm main' >/etc/apt/sources.list.d/bookworm-mesa.list

apt-get update

if ! apt-get install -y --no-install-recommends -t bookworm mesa-va-drivers; then
  echo "WARN: bookworm mesa-va-drivers apt install failed; extracting d3d12 driver only"
  install_from_bookworm_deb || {
    echo "FAIL: could not install or extract d3d12_drv_video.so" >&2
    exit 1
  }
fi

driver="$(find_d3d12_driver)"
if [ -z "$driver" ]; then
  echo "FAIL: d3d12_drv_video.so still missing" >&2
  exit 1
fi

echo "Installed d3d12 VA driver: $driver"
