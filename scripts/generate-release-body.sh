#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SRC_DIR:-${REPO_ROOT}/src}"

# shellcheck source=scripts/version-gates.sh
source "${SCRIPT_DIR}/version-gates.sh"
# shellcheck source=scripts/release-deps.sh
source "${SCRIPT_DIR}/release-deps.sh"

REQUESTED_FFMPEG_VERSION="${FFMPEG_VERSION:-}"

# Load default VERSION/COMMIT variables from fetch-sources.sh without running fetches.
while IFS= read -r line; do
  if [[ "$line" =~ ^:\ \"\$\{([A-Za-z0-9_]+(_VERSION|_COMMIT)):=([^}]*)\}\"$ ]]; then
    var="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[3]}"
    if [[ "$val" != *'$'* ]]; then
      printf -v "$var" '%s' "$val"
    fi
  fi
done < "${REPO_ROOT}/fetch-sources.sh"

if [ -n "$REQUESTED_FFMPEG_VERSION" ]; then
  FFMPEG_VERSION="$REQUESTED_FFMPEG_VERSION"
fi
FFMPEG_VERSION="${FFMPEG_VERSION:-$("${SCRIPT_DIR}/read-ffmpeg-version.sh")}"
ALPINE_VERSION="${ALPINE_VERSION:-alpine:3.22}"

lookup_var() {
  local name=$1
  if [ -z "$name" ]; then
    echo ""
    return
  fi
  printf '%s' "${!name-}"
}

resolve_src_commit() {
  local glob=$1 commit_var=$2
  local dir commit

  if [ -n "$commit_var" ]; then
    commit="$(lookup_var "$commit_var")"
    if [ -n "$commit" ]; then
      printf '%s' "$commit"
      return
    fi
  fi

  shopt -s nullglob
  for dir in "${SRC_DIR}/${glob}"; do
    if [ -d "${dir}/.git" ]; then
      git -C "$dir" rev-parse HEAD
      return
    fi
  done
  shopt -u nullglob

  printf '%s' "—"
}

decode_label() {
  if release_dep_in_decode "$1" "$FFMPEG_VERSION"; then
    printf 'Yes'
  else
    printf 'No'
  fi
}

version_label() {
  local version_var=$1 commit_var=$2 src_glob=$3
  local version commit

  version="$(lookup_var "$version_var")"
  if [ -n "$version" ]; then
    printf '%s' "$version"
    return
  fi
  if [ -n "$commit_var" ]; then
    commit="$(lookup_var "$commit_var")"
    if [ -n "$commit" ]; then
      printf '%s' "$commit"
      return
    fi
  fi
  if [ "$src_glob" = "__alpine__" ]; then
    printf 'Alpine (%s)' "$ALPINE_VERSION"
    return
  fi
  printf '%s' "—"
}

write_release_body() {
  printf 'Static FFmpeg build **%s** — dependency versions and commits.\n\n' "$FFMPEG_VERSION"
  printf '| Component | Version | Commit | In decode build |\n'
  printf '| --- | --- | --- | --- |\n'

  local row name version_var commit_var src_glob gate
  for row in "${RELEASE_DEP_ROWS[@]}"; do
    IFS='|' read -r name version_var commit_var src_glob gate <<< "$row"
    printf '| %s | %s | `%s` | %s |\n' \
      "$name" \
      "$(version_label "$version_var" "$commit_var" "$src_glob")" \
      "$(resolve_src_commit "$src_glob" "$commit_var")" \
      "$(decode_label "$gate")"
  done

  printf '\n**In decode build** reflects the decode-only image (`DECODE_ONLY=true`): encode-only libraries and wrappers omitted where FFmpeg provides native decoders.\n'
}

OUTPUT=${1:-/dev/stdout}
write_release_body > "$OUTPUT"
