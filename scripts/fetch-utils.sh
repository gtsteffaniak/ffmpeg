#!/bin/bash
# Archive download validation for scripts/fetch-sources.sh (no side effects when sourced).

archive_is_valid() {
  local file=$1
  local size sig tar_magic

  [ -f "$file" ] || return 1
  size=$(wc -c <"$file" | tr -d ' ')
  [ "$size" -gt 100 ] || return 1

  sig=$(head -c 2 "$file" | od -An -tx1 | tr -d ' \n')
  if [ "$sig" = "1f8b" ]; then
    return 0
  fi

  sig=$(head -c 6 "$file" | od -An -tx1 | tr -d ' \n')
  if [ "$sig" = "fd377a585a00" ]; then
    return 0
  fi

  sig=$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')
  if [ "$sig" = "425a68" ]; then
    return 0
  fi

  tar_magic=$(dd if="$file" bs=1 skip=257 count=5 2>/dev/null | tr -d '\0')
  if [ "$tar_magic" = "ustar" ]; then
    return 0
  fi

  return 1
}

download_archive() {
  local name=$1 url=$2 out_file=$3
  shift 3
  local extra_urls=("$@")

  local attempt_url
  for attempt_url in "$url" "${extra_urls[@]}"; do
    [ -z "$attempt_url" ] && continue
    echo "--- Downloading $name from $attempt_url ---"
    rm -f "$out_file"
    if wget "${WGET_OPTS[@]}" --user-agent="$WGET_USER_AGENT" -O "$out_file" "$attempt_url" && \
      archive_is_valid "$out_file"; then
      return 0
    fi
    echo "Invalid or failed download for $name from $attempt_url" >&2
    rm -f "$out_file"
  done

  echo "All download attempts failed for $name" >&2
  return 1
}
