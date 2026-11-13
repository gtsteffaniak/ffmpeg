#!/bin/bash
# Resolve catalog FFmpeg version vs published release tag (optional suffix).
# Inputs: CATALOG_VERSION (required), INPUT_VERSION, TAG_SUFFIX (optional).
# Writes version, tag, prerelease to GITHUB_OUTPUT when set; otherwise prints them.
set -euo pipefail

CATALOG_VERSION="${CATALOG_VERSION:?CATALOG_VERSION required}"
INPUT_VERSION="${INPUT_VERSION:-}"
TAG_SUFFIX="${TAG_SUFFIX:-}"

# Suffixes that collide with image-variant tags published for the bare
# catalog version (see release.yml / Makefile). A suffixed TAG is
# <catalog>-<suffix>; if that equals any variant of <catalog>, the release
# would overwrite that variant's image on Docker Hub and GHCR.
#   release.yml FULL_IMAGE      -> :<tag>-<amd64|arm64>
#   release.yml DECODE_IMAGE    -> :<tag>-decode-<amd64|arm64>
#   release.yml GPU_IMAGE       -> :<tag>-gpu
#   release.yml merge manifests -> :<tag> and :<tag>-decode
#   Makefile ci-merge-manifest-decode -> :<tag>-decode
is_reserved_suffix() {
  local s="$1"
  case "$s" in
    amd64|arm64|gpu|decode|decode-amd64|decode-arm64)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

validate_tag_suffix() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  case "$s" in
    -*) echo "tag_suffix must not start with a hyphen: ${s}" >&2; return 1 ;;
  esac
  # Validate the entire Bash string (not per-line like grep -Eq) so a
  # multiline suffix cannot smuggle extra positional outputs.
  if [[ ! "$s" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]]; then
    echo "Invalid tag_suffix ${s}: use only [0-9A-Za-z.-] with no leading hyphen" >&2
    return 1
  fi
  if is_reserved_suffix "$s"; then
    echo "tag_suffix '${s}' collides with an image-variant tag" >&2
    echo "Reserved suffixes: amd64 arm64 gpu decode decode-amd64 decode-arm64" >&2
    return 1
  fi
}

VERSION="$CATALOG_VERSION"
if [ -n "$INPUT_VERSION" ]; then
  if [ "$INPUT_VERSION" = "$CATALOG_VERSION" ]; then
    VERSION="$CATALOG_VERSION"
  elif [ "${INPUT_VERSION#${CATALOG_VERSION}-}" != "$INPUT_VERSION" ] && [ -n "${INPUT_VERSION#${CATALOG_VERSION}-}" ]; then
    PARSED_SUFFIX="${INPUT_VERSION#${CATALOG_VERSION}-}"
    VERSION="$CATALOG_VERSION"
    if [ -n "$TAG_SUFFIX" ] && [ "$TAG_SUFFIX" != "$PARSED_SUFFIX" ]; then
      echo "version ${INPUT_VERSION} implies suffix ${PARSED_SUFFIX}, but tag_suffix is ${TAG_SUFFIX}" >&2
      exit 1
    fi
    TAG_SUFFIX="$PARSED_SUFFIX"
  else
    echo "Manual version ${INPUT_VERSION} does not match catalog ${CATALOG_VERSION}" >&2
    exit 1
  fi
fi

validate_tag_suffix "$TAG_SUFFIX"

TAG="$VERSION"
PRERELEASE=false
if [ -n "$TAG_SUFFIX" ]; then
  TAG="${VERSION}-${TAG_SUFFIX}"
  PRERELEASE=true
fi

# Defense in depth: the resolved TAG itself must not equal a variant tag
# of the bare catalog version, regardless of how it was derived.
# (This catches both explicit TAG_SUFFIX and suffixes implied by
# INPUT_VERSION; validate_tag_suffix above already rejects those, but the
# TAG check guards any future code path that bypasses it.)
if [ -n "$TAG_SUFFIX" ]; then
  for _variant in "-gpu" "-decode" "-amd64" "-arm64" "-decode-amd64" "-decode-arm64"; do
    if [ "$TAG" = "${VERSION}${_variant}" ]; then
      echo "tag ${TAG} collides with an image-variant tag" >&2
      exit 1
    fi
  done
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${VERSION}"
    echo "tag=${TAG}"
    echo "prerelease=${PRERELEASE}"
  } >> "$GITHUB_OUTPUT"
else
  printf '%s\n' "$VERSION" "$TAG" "$PRERELEASE"
fi
