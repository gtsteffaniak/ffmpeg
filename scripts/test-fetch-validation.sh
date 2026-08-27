#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WGET_OPTS=(--timeout=5 --tries=1)
WGET_USER_AGENT="ffmpeg-build-test/1.0"
# shellcheck source=scripts/fetch-utils.sh
source "${SCRIPT_DIR}/fetch-utils.sh"

assert_valid() {
  local desc=$1 file=$2
  if archive_is_valid "$file"; then
    echo "OK: $desc accepted"
  else
    echo "FAIL: $desc should be valid" >&2
    exit 1
  fi
}

assert_invalid() {
  local desc=$1 file=$2
  if archive_is_valid "$file"; then
    echo "FAIL: $desc should be rejected" >&2
    exit 1
  fi
  echo "OK: $desc rejected"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf '<html><body>error</body></html>' >"${TMPDIR}/fake.html"
assert_invalid "HTML error page" "${TMPDIR}/fake.html"

printf '\001\002' >"${TMPDIR}/tiny.bin"
assert_invalid "tiny file" "${TMPDIR}/tiny.bin"

dd if=/dev/urandom bs=1024 count=2 2>/dev/null | gzip >"${TMPDIR}/valid.gz"
assert_valid "gzip archive" "${TMPDIR}/valid.gz"

echo "All fetch validation checks passed"
