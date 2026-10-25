#!/bin/bash
# Resolve catalog FFmpeg version vs published release tag (optional suffix).
# Inputs: CATALOG_VERSION (required), INPUT_VERSION, TAG_SUFFIX (optional).
# Writes version, tag, prerelease to GITHUB_OUTPUT when set; otherwise prints them.
set -euo pipefail

CATALOG_VERSION="${CATALOG_VERSION:?CATALOG_VERSION required}"
INPUT_VERSION="${INPUT_VERSION:-}"
TAG_SUFFIX="${TAG_SUFFIX:-}"

validate_tag_suffix() {
  local s="$1"
  if [ -z "$s" ]; then
    return 0
  fi
  case "$s" in
    -*) echo "tag_suffix must not start with a hyphen: ${s}" >&2; return 1 ;;
  esac
  if ! printf '%s' "$s" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z.-]*$'; then
    echo "Invalid tag_suffix ${s}: use only [0-9A-Za-z.-] with no leading hyphen" >&2
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

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${VERSION}"
    echo "tag=${TAG}"
    echo "prerelease=${PRERELEASE}"
  } >> "$GITHUB_OUTPUT"
else
  printf '%s\n' "$VERSION" "$TAG" "$PRERELEASE"
fi
