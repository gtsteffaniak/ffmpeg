#!/bin/bash
# Normalize BUILD_VARIANT (full | static) and legacy DECODE_ONLY.
# DECODE_ONLY=true historically meant "decode-only"; that variant is now
# BUILD_VARIANT=static with software encoders enabled (no GPU dlopen).
set -eu

normalize_build_variant() {
  if [ -n "${BUILD_VARIANT:-}" ]; then
    case "$BUILD_VARIANT" in
      full|static) ;;
      *)
        echo "Invalid BUILD_VARIANT=${BUILD_VARIANT} (expected full or static)" >&2
        return 1
        ;;
    esac
  elif [ "${DECODE_ONLY:-false}" = "true" ]; then
    BUILD_VARIANT=static
  else
    BUILD_VARIANT=full
  fi
  export BUILD_VARIANT
}

# True when building the Alpine scratch static image (no GPU userspace dlopen).
is_static_variant() {
  normalize_build_variant
  [ "$BUILD_VARIANT" = "static" ]
}
