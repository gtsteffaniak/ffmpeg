#!/bin/bash
# Fetch dependency sources listed in sources.json.
# Versions and URLs come from: go run -C tools/catalog . fetch-script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=version-gates.sh
source "${SCRIPT_DIR}/version-gates.sh"
# shellcheck source=fetch-utils.sh
source "${SCRIPT_DIR}/fetch-utils.sh"

: "${DECODE_ONLY:=false}"
if [ -z "${FFMPEG_VERSION:-}" ]; then
  FFMPEG_VERSION="$(cd "$REPO_ROOT" && go run -C tools/catalog . read release.ffmpeg_version)"
fi
export FFMPEG_VERSION DECODE_ONLY

mkdir -p "${REPO_ROOT}/src"
cd "${REPO_ROOT}/src"
ROOT_DIR=$(pwd)

WGET_OPTS=(
  --retry-on-host-error
  --retry-on-http-error=403,429,500,502,503,504
  --waitretry=5
  --timeout=60
  --tries=3
)
WGET_USER_AGENT="ffmpeg-build/1.0 (+https://github.com/gtsteffaniak/ffmpeg)"

fetch_values_archive() {
  local name=$1 version=$2 url=$3
  local strip_components=${4:-0}
  local dir="${name}-${version}"

  if [[ -d "$dir" ]]; then
    echo "Skipping $name, directory exists: $dir"
    return
  fi

  echo "--- Downloading $name ---"
  local file="${name}.tar"
  if ! download_archive "$name" "$url" "$file"; then
    return 1
  fi

  echo "--- Extracting to $dir ---"
  tar --no-same-owner --strip-components="$strip_components" -xf "$file"
  rm -f "$file"

  for d in "$name"*; do
    if [[ -d "$d" && "$d" != "$dir" ]]; then
      mv "$d" "$dir"
      break
    fi
  done

  echo "--- Finished $dir ---"
}

fetch_values_git_tag() {
  local name=$1 version=$2 url=$3
  local dir="${name}-${version}"

  if [[ -d "$dir" ]]; then
    echo "Skipping $name, directory exists: $dir"
    return
  fi

  echo "--- Cloning $name tag ${version} ---"
  if git clone --depth 1 --branch "${version}" "$url" "$dir"; then
    :
  elif git clone --depth 1 --branch "v${version}" "$url" "$dir"; then
    echo "Using tag v${version}"
  else
    echo "Git clone failed for $name tag ${version} (also tried v${version})"
    return 1
  fi

  echo "--- Finished ${dir} ---"
}

fetch_values_git_commit() {
  local name=$1 url=$2 commit=$3

  for d in "$name"*; do
    [[ -d "$d" ]] && echo "Skipping $name, directory exists: $d" && return
  done

  echo "--- Cloning $name ---"
  if ! git clone "$url" "$name"; then
    echo "Git clone failed for $name"
    return 1
  fi

  if [[ -n "$commit" ]]; then
    echo "Checking out commit $commit"
    (cd "$name" && git checkout --recurse-submodules "$commit")
  fi

  echo "--- Cloned $name ---"
}

write_version_txt() {
  local dir=$1 version=$2
  if [[ -d "$dir" ]]; then
    echo "Writing version.txt in $dir"
    (cd "$dir" && echo "v${version}" > version.txt)
  else
    echo "Skipping version.txt ($dir not found)"
  fi
}

fetch_aom() {
  local url=$1 version=$2 commit=$3
  if [[ -d aom ]]; then
    echo "Skipping aom, directory exists"
    return
  fi
  echo "--- Cloning aom v${version} ---"
  git clone --depth 1 --branch "v${version}" "$url" aom
  (cd aom && test "$(git rev-parse HEAD)" = "$commit")
  echo "--- Finished aom at ${commit} ---"
}

fetch_uavs3d() {
  local url=$1 version=$2 commit=$3
  local dir="uavs3d-${version}"

  if [[ -d uavs3d ]]; then
    rm -rf uavs3d
  fi
  if [[ -d "$dir" ]]; then
    local current_commit
    current_commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ "$current_commit" == "$commit" ]]; then
      echo "Skipping uavs3d, already at commit ${commit}"
      return
    fi
    echo "--- Updating uavs3d to commit ${commit} ---"
    rm -rf "$dir"
  else
    echo "--- Cloning uavs3d at commit ${commit} ---"
  fi
  git clone --depth 100 "$url" "$dir"
  (cd "$dir" && git checkout "${commit}")
  echo "--- Finished ${dir} at ${commit} ---"
}

echo "Fetching sources from sources.json (FFMPEG_VERSION=${FFMPEG_VERSION}, DECODE_ONLY=${DECODE_ONLY})"
# shellcheck disable=SC1090
eval "$(cd "$REPO_ROOT" && go run -C tools/catalog . fetch-script)"

echo "All fetching and unpacking complete."
