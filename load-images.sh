#!/bin/sh
# Preload OCI images into docker-archive tarballs using skopeo.
#
# Usage:
#   preload-images.sh <image-list-file> <output-dir>
#
# image-list-file: one image reference per line; blank lines and # comments ignored.
# output-dir:      directory where .tar files are written (created if missing).

set -x

LIST_FILE="${1:?usage: $0 <image-list-file> <output-dir>}"
OUT_DIR="${2:?usage: $0 <image-list-file> <output-dir>}"

if [ ! -f "$LIST_FILE" ]; then
  echo "ERROR: image list not found: $LIST_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

while IFS= read -r ref || [ -n "$ref" ]; do
  # strip leading/trailing whitespace
  ref=$(echo "$ref" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  # skip blanks and comments
  case "$ref" in
    ''|\#*) continue ;;
  esac

  # filename-safe version of the ref
  fname=$(echo "$ref" | tr '/:@' '___').tar

  # the load-time tag inside the archive: strip any @digest suffix
  load_tag=$(echo "$ref" | sed 's/@.*//')

  echo "==> $ref"
  echo "    -> $OUT_DIR/$fname (tag: $load_tag)"

  skopeo copy \
    "docker://$ref" \
    "docker-archive:$OUT_DIR/$fname:$load_tag"

done < "$LIST_FILE"
