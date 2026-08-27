#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/version-gates.sh
source "${SCRIPT_DIR}/version-gates.sh"

assert() {
  local desc=$1 expected=$2
  shift 2
  if "$@"; then
    got=0
  else
    got=1
  fi
  if [ "$got" -ne "$expected" ]; then
    echo "FAIL: $desc (expected exit $expected, got $got)" >&2
    exit 1
  fi
  echo "OK: $desc"
}

assert "9.0.1 >= 9.0.0" 0 ffmpeg_version_ge "9.0.1" "9.0.0"
assert "8.1.1 < 9.0.0" 1 ffmpeg_version_ge "8.1.1" "9.0.0"

assert "full build needs libwebp" 0 needs_libwebp "9.0.1" "false"
assert "decode 9.0 skips libwebp" 1 needs_libwebp "9.0.1" "true"
assert "decode 8.1 keeps libwebp install path" 0 needs_libwebp "8.1.1" "true"

assert "decode skips openjpeg" 1 needs_openjpeg "9.0.1" "true"
assert "full needs openjpeg" 0 needs_openjpeg "9.0.1" "false"

echo "All version-gates checks passed"
