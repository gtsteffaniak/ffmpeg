#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="9.0.2"

run_resolve() {
  CATALOG_VERSION="$CATALOG" INPUT_VERSION="${1:-}" TAG_SUFFIX="${2:-}" \
    "${SCRIPT_DIR}/resolve-release-version.sh"
}

assert_case() {
  local desc="$1"
  local expect_version="$2"
  local expect_tag="$3"
  local expect_prerelease="$4"
  local input_version="${5:-}"
  local tag_suffix="${6:-}"
  local out
  if ! out="$(run_resolve "$input_version" "$tag_suffix" 2>/dev/null)"; then
    if [ "$expect_version" = "FAIL" ]; then
      echo "OK: $desc (expected failure)"
      return 0
    fi
    echo "FAIL: $desc — unexpected failure" >&2
    return 1
  fi
  if [ "$expect_version" = "FAIL" ]; then
    echo "FAIL: $desc — expected failure but succeeded" >&2
    return 1
  fi
  local got_version got_tag got_prerelease
  got_version="$(echo "$out" | sed -n '1p')"
  got_tag="$(echo "$out" | sed -n '2p')"
  got_prerelease="$(echo "$out" | sed -n '3p')"
  if [ "$got_version" != "$expect_version" ] || [ "$got_tag" != "$expect_tag" ] || [ "$got_prerelease" != "$expect_prerelease" ]; then
    echo "FAIL: $desc — got version=$got_version tag=$got_tag prerelease=$got_prerelease" >&2
    return 1
  fi
  echo "OK: $desc"
}

assert_case "no input" "9.0.2" "9.0.2" "false"
assert_case "version=9.0.2" "9.0.2" "9.0.2" "false" "9.0.2"
assert_case "tag_suffix=full-gpu" "9.0.2" "9.0.2-full-gpu" "true" "" "full-gpu"
assert_case "version=9.0.2-full-gpu" "9.0.2" "9.0.2-full-gpu" "true" "9.0.2-full-gpu"
assert_case "bad suffix leading hyphen" "FAIL" "" "" "" "-gpu"
assert_case "bad suffix chars" "FAIL" "" "" "" "full_gpu"

echo "All resolve-release-version checks passed"
