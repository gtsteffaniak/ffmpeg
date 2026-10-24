#!/bin/bash
# Ensure Mesa ships the WSL2 VAAPI driver (d3d12_drv_video.so) in the full image.
# Bullseye's mesa-va-drivers is too old; pull bookworm mesa-va-drivers on amd64 when missing.
set -euo pipefail

find_d3d12_driver() {
  find /usr/lib -name 'd3d12_drv_video.so' 2>/dev/null | head -n1
}

if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "Skipping d3d12 VA driver install (not amd64)"
  exit 0
fi

if [ -n "$(find_d3d12_driver)" ]; then
  echo "d3d12 VA driver already present: $(find_d3d12_driver)"
  exit 0
fi

echo "d3d12_drv_video.so not found after base mesa-va-drivers; installing bookworm mesa-va-drivers"

cat >/etc/apt/preferences.d/mesa-bookworm <<'EOF'
Package: mesa-va-drivers
Pin: release n=bookworm
Pin-Priority: 500
EOF

echo 'deb http://deb.debian.org/debian bookworm main' >/etc/apt/sources.list.d/bookworm-mesa.list

apt-get update
apt-get install -y --no-install-recommends -t bookworm mesa-va-drivers

driver="$(find_d3d12_driver)"
if [ -z "$driver" ]; then
  echo "FAIL: d3d12_drv_video.so still missing after bookworm mesa-va-drivers" >&2
  exit 1
fi

echo "Installed d3d12 VA driver: $driver"
