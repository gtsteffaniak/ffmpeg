#!/bin/sh
# Verify dynamically linked ffmpeg only depends on an allowlisted set of libs.
set -eu

BIN="${1:?binary path required}"
ALLOWLIST="${2:-}"

if [ -z "$ALLOWLIST" ]; then
  ALLOWLIST='^lib(c|m|dl|pthread|va|va-drm|va-x11|vpl|mfx|OpenCL|vulkan|nvidia-encode|nvidia-ml|stdc\+\+|gcc_s|gomp)\.so'
fi

if ! file "$BIN" | grep -q 'dynamically linked'; then
  echo "Expected dynamically linked binary: $BIN" >&2
  file "$BIN"
  exit 1
fi

bad=0
while read -r line; do
  case "$line" in
    *'=>'*) lib=$(echo "$line" | awk '{print $3}')
      ;;
    *) continue ;;
  esac
  if ! echo "$lib" | grep -Eq "$ALLOWLIST"; then
    echo "Unexpected dynamic dependency: $lib" >&2
    bad=1
  fi
done <<EOF
$(ldd "$BIN" 2>/dev/null || true)
EOF

if [ "$bad" -ne 0 ]; then
  echo "ldd:" >&2
  ldd "$BIN" >&2 || true
  exit 1
fi

echo "ldd allowlist OK for $BIN"
