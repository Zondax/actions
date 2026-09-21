#!/usr/bin/env bash
set -euo pipefail

rclone_bin="$(command -v rclone || true)"
if [ -z "$rclone_bin" ]; then
  rclone_bin="$(mise which rclone 2>/dev/null || true)"
fi
if [ -z "$rclone_bin" ]; then
  echo '::error::rclone not found (install it or pin it in mise.toml)'
  exit 1
fi

if [ -z "${RCLONE_CONFIG_S3_ACCESS_KEY_ID:-}" ] || [ -z "${BUCKET:-}" ] || [ -z "${RCLONE_CONFIG_S3_ENDPOINT:-}" ]; then
  echo '::error::bucket, endpoint, and access_key_id are required'
  exit 1
fi

case "$MODE" in
  copy | sync) ;;
  *)
    echo "::error::mode must be copy or sync, got ${MODE}"
    exit 1
    ;;
esac

src="$SRC"
if [[ "$src" != s3:* ]]; then
  if [ ! -d "$src" ]; then
    echo "::error::local source is not a directory: $src"
    exit 1
  fi
  [[ "$src" == */ ]] || src="${src}/"
fi

dest_prefix="$DEST_PREFIX"
if [[ "$dest_prefix" == ./* ]] || [[ "$dest_prefix" == /* ]] || [[ "$dest_prefix" == ../* ]]; then
  dest="$dest_prefix"
  mkdir -p "$dest"
  [[ "$dest" == */ ]] || dest="${dest}/"
else
  dest_prefix="${dest_prefix#/}"
  [[ "$dest_prefix" == */ ]] || dest_prefix="${dest_prefix}/"
  dest="s3:${BUCKET}/${dest_prefix}"
fi

count="$("$rclone_bin" ls "$src" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${count:-0}" = '0' ]; then
  if [ "$REQUIRED" = 'true' ]; then
    echo "::error::nothing at $src"
    exit 1
  fi
  echo "No objects at $src; skip"
  echo "count=0" >> "$GITHUB_OUTPUT"
  echo "dest=$dest" >> "$GITHUB_OUTPUT"
  exit 0
fi

# shellcheck disable=SC2086
"$rclone_bin" "$MODE" "$src" "$dest" --progress $EXTRA_ARGS
echo "count=$count" >> "$GITHUB_OUTPUT"
echo "dest=$dest" >> "$GITHUB_OUTPUT"
echo "$MODE $count objects -> $dest" >> "$GITHUB_STEP_SUMMARY"
