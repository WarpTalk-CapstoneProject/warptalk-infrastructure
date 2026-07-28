#!/bin/sh
set -eu

: "${QDRANT_IMAGE_DIGEST:?QDRANT_IMAGE_DIGEST is required}"

input="$(mktemp "${TMPDIR:-/tmp}/warptalk-qdrant-render.XXXXXX")"
trap 'rm -f "$input"' EXIT INT TERM
tee "$input" >/dev/null

grep -Fq 'docker.io/qdrant/qdrant:v1.18.2' "$input" || {
  echo "Qdrant runtime image expected by post-renderer was not found" >&2
  exit 1
}
sed \
  -e "s#docker.io/qdrant/qdrant:v1.18.2#docker.io/qdrant/qdrant:v1.18.2@${QDRANT_IMAGE_DIGEST}#g" \
  "$input"
