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
assert "vaapi is default build" 0 needs_vaapi_build
assert "v4l2-m2m is default build" 0 needs_v4l2_m2m_build
assert "eval_fetch_gate needs_vaapi_build" 0 eval_fetch_gate needs_vaapi_build "9.0.1" "true"
assert "eval_fetch_gate needs_v4l2_m2m_build" 0 eval_fetch_gate needs_v4l2_m2m_build "9.0.1" "true"

assert "7.0 full needs modern codecs build" 0 needs_modern_codecs_build "7.0.0" "false"
assert "6.1 skips modern codecs build" 1 needs_modern_codecs_build "6.1.3" "false"
assert "7.0 decode skips modern codecs build" 1 needs_modern_codecs_build "7.0.0" "true"

default_version="$(cd "${SCRIPT_DIR}/.." && go run -C tools/catalog . read release.ffmpeg_version)"
if [ -z "$default_version" ]; then
  echo "FAIL: go run -C tools/catalog . read release.ffmpeg_version returned empty" >&2
  exit 1
fi
echo "OK: sources.json ffmpeg version=${default_version}"

override="$(cd "${SCRIPT_DIR}/.." && FFMPEG_VERSION=8.1.2 go run -C tools/catalog . read release.ffmpeg_version)"
if [ "$override" != "8.1.2" ]; then
  echo "FAIL: ffmpeg version env override (got ${override})" >&2
  exit 1
fi
echo "OK: ffmpeg version env override"

assert "eval_fetch_gate always" 0 eval_fetch_gate always "9.0.1" "true"

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
echo "  --enable-vaapi"
echo "  --enable-v4l2-m2m"
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
  *"--enable-vaapi"*) ;;
  *"--enable-v4l2-m2m"*) ;;
  *"--enable-libxeve"*) echo "FAIL: 6.1 configure should not offer libxeve" >&2; exit 1 ;;
  *) echo "FAIL: 6.1 configure should enable libvpl, vaapi, and v4l2-m2m" >&2; exit 1 ;;
esac
echo "OK: build_ffmpeg_configure_flags for 6.1.3"

cat >"${TMPDIR}/configure-gpu" <<'EOF'
#!/bin/sh
echo "  --disable-doc"
echo "  --enable-vaapi"
echo "  --enable-libvpl"
echo "  --enable-libdrm"
echo "  --enable-vulkan"
echo "  --enable-opencl"
echo "  --enable-ffnvcodec"
echo "  --enable-nvenc"
echo "  --enable-nvdec"
echo "  --enable-cuvid"
echo "  --enable-amf"
echo "  --enable-v4l2-m2m"
echo "  --enable-libzimg"
echo "  --enable-fontconfig"
echo "  --enable-gray"
echo "  --enable-iconv"
echo "  --enable-lcms2"
echo "  --enable-libxml2"
echo "  --enable-libdav1d"
echo "  --enable-libass"
echo "  --enable-libfreetype"
echo "  --enable-libfribidi"
echo "  --enable-libharfbuzz"
echo "  --enable-libsoxr"
echo "  --enable-libsnappy"
echo "  --enable-libvpx"
echo "  --enable-libaom"
echo "  --enable-libopenjpeg"
echo "  --enable-libvorbis"
echo "  --enable-libwebp"
echo "  --enable-nonfree"
echo "  --enable-libx264"
echo "  --enable-librav1e"
echo "  --enable-libsvtav1"
echo "  --enable-libx265"
echo "  --enable-libxeve"
echo "  --enable-libxevd"
echo "  --enable-libvvenc"
echo "  --enable-libdavs2"
echo "  --enable-libmysofa"
echo "  --enable-libuavs3d"
echo "  --enable-libvidstab"
echo "  --enable-libvmaf"
echo "  --enable-libvo-amrwbenc"
echo "  --enable-libmp3lame"
echo "  --enable-static"
EOF
chmod +x "${TMPDIR}/configure-gpu"

build_gpu_configure_flags "${TMPDIR}/configure-gpu" "9.0.1" "false"
case "$BASE_FLAGS $FEATURES" in
  *"--enable-vaapi"*) ;;
  *) echo "FAIL: GPU configure should enable vaapi" >&2; exit 1 ;;
esac
case "$BASE_FLAGS $FEATURES" in
  *"--enable-static"*) echo "FAIL: GPU configure must not emit --enable-static" >&2; exit 1 ;;
  *) ;;
esac
for _gpu_flag in --enable-libvpl --enable-vulkan --enable-opencl --enable-ffnvcodec --enable-nvenc --enable-nvdec --enable-amf --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libdav1d; do
  case "$BASE_FLAGS $FEATURES" in
    *"$_gpu_flag"*) ;;
    *) echo "FAIL: GPU configure should enable $_gpu_flag" >&2; exit 1 ;;
  esac
done
echo "OK: build_gpu_configure_flags for 9.0.1"

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

# ---- resolve-release-version.sh: reserved suffix + a-f cases ----
# A suffixed TAG is <catalog>-<suffix>. If it equals an image-variant tag
# of the bare catalog version, the release would overwrite that variant's
# image (see resolve-release-version.sh comments). Reserved suffixes must
# fail via tag_suffix AND via a suffix implied by INPUT_VERSION.
RESOLVER="${SCRIPT_DIR}/resolve-release-version.sh"
RCATALOG="9.0.2"

run_resolver_ok() {
  local desc="$1" input="$2" suffix="$3" exp_version="$4" exp_tag="$5" exp_pre="$6"
  local out
  out="$(CATALOG_VERSION="$RCATALOG" INPUT_VERSION="$input" TAG_SUFFIX="$suffix" GITHUB_OUTPUT= "$RESOLVER")" || {
    echo "FAIL: $desc (resolver exited nonzero)" >&2
    return 1
  }
  local got_version got_tag got_pre
  got_version="$(printf '%s\n' "$out" | sed -n '1p')"
  got_tag="$(printf '%s\n' "$out" | sed -n '2p')"
  got_pre="$(printf '%s\n' "$out" | sed -n '3p')"
  if [ "$got_version" != "$exp_version" ] || [ "$got_tag" != "$exp_tag" ] || [ "$got_pre" != "$exp_pre" ]; then
    echo "FAIL: $desc (got version=$got_version tag=$got_tag prerelease=$got_pre, want $exp_version $exp_tag $exp_pre)" >&2
    return 1
  fi
  echo "OK: $desc (version=$got_version tag=$got_tag prerelease=$got_pre)"
}

run_resolver_fail() {
  local desc="$1" input="$2" suffix="$3" err_substr="$4"
  local err
  if err="$(CATALOG_VERSION="$RCATALOG" INPUT_VERSION="$input" TAG_SUFFIX="$suffix" GITHUB_OUTPUT= "$RESOLVER" 2>&1)"; then
    echo "FAIL: $desc (resolver unexpectedly succeeded)" >&2
    return 1
  fi
  case "$err" in
    *"$err_substr"*) echo "OK: $desc (failed as expected: $err_substr)" ;;
    *) echo "FAIL: $desc (error missing '$err_substr', got: $err)" >&2; return 1 ;;
  esac
}

# (a) no INPUT -> version=catalog tag=catalog prerelease=false
run_resolver_ok "resolve (a) no input" "" "" "$RCATALOG" "$RCATALOG" "false"
# (b) INPUT=catalog -> ok
run_resolver_ok "resolve (b) input=catalog" "$RCATALOG" "" "$RCATALOG" "$RCATALOG" "false"
# (c) INPUT=catalog-full-gpu -> version=catalog tag=catalog-full-gpu prerelease=true
# full-gpu is the documented branch-test suffix; verified not a real
# published tag (Docker Hub 9.0.2-full-gpu is absent; only transient
# per-arch staging tags briefly existed), and it collides with no variant.
run_resolver_ok "resolve (c) input=catalog-full-gpu" "${RCATALOG}-full-gpu" "" "$RCATALOG" "${RCATALOG}-full-gpu" "true"
# (c2) tag_suffix=full-gpu (explicit) -> ok
run_resolver_ok "resolve (c2) tag_suffix=full-gpu" "" "full-gpu" "$RCATALOG" "${RCATALOG}-full-gpu" "true"
# (c3) tag_suffix=rc1 -> ok
run_resolver_ok "resolve (c3) tag_suffix=rc1" "" "rc1" "$RCATALOG" "${RCATALOG}-rc1" "true"
# (d) INPUT=catalog-full-gpu with mismatched TAG_SUFFIX=other -> fails
run_resolver_fail "resolve (d) suffix mismatch" "${RCATALOG}-full-gpu" "other" "implies suffix"
# (e) INPUT=9.9.9 -> fails with 'does not match catalog'
run_resolver_fail "resolve (e) unknown version" "9.9.9" "" "does not match catalog"
# (f) TAG_SUFFIX=-leading -> fails
run_resolver_fail "resolve (f) leading hyphen suffix" "" "-leading" "must not start with a hyphen"
# Reserved suffixes via tag_suffix must fail
for _rs in gpu decode amd64 arm64 decode-amd64 decode-arm64; do
  run_resolver_fail "resolve reserved tag_suffix=$_rs" "" "$_rs" "collides with an image-variant tag"
done
# Reserved suffixes implied by INPUT_VERSION must also fail (no bypass)
for _rs in gpu decode amd64 arm64 decode-amd64 decode-arm64; do
  run_resolver_fail "resolve reserved INPUT=catalog-$_rs" "${RCATALOG}-${_rs}" "" "collides with an image-variant tag"
done

echo "All version-gates checks passed"
