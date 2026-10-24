#!/bin/bash
# CI/build check: full glibc image includes Mesa d3d12 VAAPI driver for WSL2.
set -euo pipefail

ROOT="${1:-/}"

if [ ! -d "$ROOT/usr/lib" ]; then
  echo "FAIL: invalid root $ROOT" >&2
  exit 1
fi

driver="$(find "$ROOT/usr/lib" -name 'd3d12_drv_video.so' 2>/dev/null | head -n1)"
if [ -z "$driver" ]; then
  echo "FAIL: d3d12_drv_video.so not found under ${ROOT}/usr/lib" >&2
  exit 1
fi

echo "OK: WSL VAAPI driver present at ${driver#"$ROOT"}"
