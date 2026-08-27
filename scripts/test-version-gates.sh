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
assert "6.1 >= 6.0.0" 0 ffmpeg_version_ge "6.1" "6.0.0"
assert "5.1 < 6.0.0" 1 ffmpeg_version_ge "5.1" "6.0.0"
assert "7.0 >= 7.0.0" 0 ffmpeg_version_ge "7.0" "7.0.0"
assert "6.1 < 7.0.0" 1 ffmpeg_version_ge "6.1" "7.0.0"

assert "full build needs libwebp" 0 needs_libwebp "9.0.1" "false"
assert "decode 9.0 skips libwebp" 1 needs_libwebp "9.0.1" "true"
assert "decode 8.1 keeps libwebp install path" 0 needs_libwebp "8.1.1" "true"

assert "decode skips openjpeg" 1 needs_openjpeg "9.0.1" "true"
assert "full needs openjpeg" 0 needs_openjpeg "9.0.1" "false"

assert "6.0 needs libvpl build" 0 needs_libvpl_build "6.0.0"
assert "5.1 skips libvpl build" 1 needs_libvpl_build "5.1.6"

assert "7.0 full needs modern codecs build" 0 needs_modern_codecs_build "7.0.0" "false"
assert "6.1 skips modern codecs build" 1 needs_modern_codecs_build "6.1.3" "false"
assert "7.0 decode skips modern codecs build" 1 needs_modern_codecs_build "7.0.0" "true"

default_version="$("${SCRIPT_DIR}/read-ffmpeg-version.sh")"
if [ -z "$default_version" ]; then
  echo "FAIL: read-ffmpeg-version.sh returned empty" >&2
  exit 1
fi
echo "OK: read-ffmpeg-version default=${default_version}"

override="$(FFMPEG_VERSION=8.1.2 "${SCRIPT_DIR}/read-ffmpeg-version.sh")"
if [ "$override" != "8.1.2" ]; then
  echo "FAIL: read-ffmpeg-version env override (got ${override})" >&2
  exit 1
fi
echo "OK: read-ffmpeg-version env override"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat >"${TMPDIR}/configure" <<'EOF'
#!/bin/sh
echo "  --enable-libvpl"
echo "  --enable-libx264"
echo "  --enable-libxeve"
EOF
chmod +x "${TMPDIR}/configure"

cat >"${TMPDIR}/configure-51" <<'EOF'
#!/bin/sh
echo "  --enable-libx264"
echo "  --enable-libdav1d"
EOF
chmod +x "${TMPDIR}/configure-51"

cat >"${TMPDIR}/configure-61" <<'EOF'
#!/bin/sh
echo "  --enable-libvpl"
echo "  --enable-libx264"
EOF
chmod +x "${TMPDIR}/configure-61"

assert "configure_supports_flag finds libvpl" 0 configure_supports_flag "${TMPDIR}/configure" "--enable-libvpl"
assert "configure_supports_flag rejects unknown" 1 configure_supports_flag "${TMPDIR}/configure" "--enable-libharfbuzz"

FEATURES=""
append_if_supported "${TMPDIR}/configure" FEATURES "--enable-libx264"
append_if_supported "${TMPDIR}/configure" FEATURES "--enable-libharfbuzz"
if [ "$FEATURES" != " --enable-libx264" ]; then
  echo "FAIL: append_if_supported (got '${FEATURES}')" >&2
  exit 1
fi
echo "OK: append_if_supported"

build_ffmpeg_configure_flags "${TMPDIR}/configure-51" "5.1.6" "false"
case "$BASE_FLAGS $FEATURES" in
  *"--enable-libvpl"*) echo "FAIL: 5.1 configure should not offer libvpl" >&2; exit 1 ;;
  *"--enable-libx264"*) ;;
  *) echo "FAIL: 5.1 configure should enable libx264" >&2; exit 1 ;;
esac
echo "OK: build_ffmpeg_configure_flags for 5.1.6"

build_ffmpeg_configure_flags "${TMPDIR}/configure-61" "6.1.3" "false"
case "$BASE_FLAGS $FEATURES" in
  *"--enable-libvpl"*) ;;
  *"--enable-libxeve"*) echo "FAIL: 6.1 configure should not offer libxeve" >&2; exit 1 ;;
  *) echo "FAIL: 6.1 configure should enable libvpl" >&2; exit 1 ;;
esac
echo "OK: build_ffmpeg_configure_flags for 6.1.3"

mkdir -p "${TMPDIR}/ffmpeg/libavcodec"
cat >"${TMPDIR}/ffmpeg/libavcodec/libsvtav1.c" <<'EOF'
svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc, &svt_enc->enc_params);
EOF
(
  cd "${TMPDIR}/ffmpeg"
  assert "needs_svtav1_api_patch detects old API" 0 needs_svtav1_api_patch
)

cat >"${TMPDIR}/ffmpeg/libavcodec/libsvtav1.c" <<'EOF'
svt_av1_enc_init_handle(&svt_enc->svt_handle, &svt_enc->enc_params);
EOF
(
  cd "${TMPDIR}/ffmpeg"
  assert "needs_svtav1_api_patch skips new API" 1 needs_svtav1_api_patch
)

echo "All version-gates checks passed"
