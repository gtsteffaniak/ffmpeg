#!/bin/bash
# Print the FFmpeg version used for fetch, Docker build-args, and release tags.
# Precedence: FFMPEG_VERSION env > fetch-sources.sh default.
set -eu

if [ -n "${FFMPEG_VERSION:-}" ]; then
  echo "$FFMPEG_VERSION"
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FETCH_SOURCES="${ROOT_DIR}/fetch-sources.sh"

if [ ! -f "$FETCH_SOURCES" ]; then
  echo "fetch-sources.sh not found at ${FETCH_SOURCES}" >&2
  exit 1
fi

version="$(grep 'FFMPEG_VERSION:=' "$FETCH_SOURCES" | head -1 | sed -E 's/.*FFMPEG_VERSION:=([0-9.]+).*/\1/')"
if [ -z "$version" ]; then
  echo "Could not read FFMPEG_VERSION from fetch-sources.sh" >&2
  exit 1
fi

echo "$version"
