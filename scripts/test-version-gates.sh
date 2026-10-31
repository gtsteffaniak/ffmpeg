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

BUILD_VARIANT=full
export BUILD_VARIANT
assert "full needs libwebp" 0 needs_libwebp "9.0.1" "full"
assert "full needs libvpl build" 0 needs_libvpl_build "6.0.0"
assert "full needs vaapi build" 0 needs_vaapi_build

BUILD_VARIANT=static
export BUILD_VARIANT
assert "static skips vaapi" 1 needs_vaapi_build
assert "static skips libvpl build" 1 needs_libvpl_build "9.0.1"
assert "static skips libwebp" 1 needs_libwebp "9.0.1" "static"
assert "static skips x265 build" 1 needs_x265_build
assert "eval_fetch_gate needs_vaapi_build static" 1 eval_fetch_gate needs_vaapi_build "9.0.1" "static"

BUILD_VARIANT=full
export BUILD_VARIANT
assert "eval_fetch_gate needs_vaapi_build full" 0 eval_fetch_gate needs_vaapi_build "9.0.1" "full"

default_version="$(cd "${SCRIPT_DIR}/.." && go run -C tools/catalog . read release.ffmpeg_version)"
test -n "$default_version"
echo "OK: sources.json ffmpeg version=${default_version}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat >"${TMPDIR}/configure-61" <<'EOF'
#!/bin/sh
echo "  --enable-libvpl"
echo "  --enable-vaapi"
echo "  --enable-v4l2-m2m"
echo "  --enable-nvenc"
echo "  --enable-vulkan"
echo "  --enable-libx264"
EOF
chmod +x "${TMPDIR}/configure-61"

build_ffmpeg_configure_flags "${TMPDIR}/configure-61" "6.1.3" "full"
case "$BASE_FLAGS $FEATURES" in
  *"--enable-libvpl"*) ;;
  *"--enable-vaapi"*) ;;
  *"--enable-libx264"*) ;;
  *"--enable-nonfree"*) echo "FAIL: full build must not enable nonfree" >&2; exit 1 ;;
  *) echo "FAIL: full 6.1 configure flags" >&2; exit 1 ;;
esac
case "$BASE_FLAGS" in
  *"--enable-ffnvcodec"*) ;;
  *"--enable-nvenc"*) ;;
  *) echo "FAIL: full build should enable ffnvcodec/nvenc in BASE_FLAGS" >&2; exit 1 ;;
esac
echo "OK: build_ffmpeg_configure_flags for full 6.1.3"

build_ffmpeg_configure_flags "${TMPDIR}/configure-61" "6.1.3" "static"
case "$BASE_FLAGS $FEATURES" in
  *"--enable-vaapi"*) echo "FAIL: static must not enable vaapi" >&2; exit 1 ;;
  *"--enable-libx264"*) ;;
  *) echo "FAIL: static should enable libx264" >&2; exit 1 ;;
esac
echo "OK: build_ffmpeg_configure_flags for static 6.1.3"

"${SCRIPT_DIR}/test-resolve-release-version.sh"

echo "All version-gates checks passed"
