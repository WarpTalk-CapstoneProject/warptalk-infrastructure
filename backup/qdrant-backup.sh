#!/bin/sh
# Create one portable collection snapshot per Qdrant collection.
set -eu

: "${QDRANT_URL:?QDRANT_URL is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

mkdir -p "$BACKUP_DIR/qdrant"
stamp="${BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
manifest="$BACKUP_DIR/qdrant/collections-$stamp.jsonl"
headers_file="$(mktemp)"
trap 'rm -f "$headers_file"' EXIT INT TERM

if [ -n "${QDRANT_API_KEY:-}" ]; then
  printf 'api-key: %s\n' "$QDRANT_API_KEY" > "$headers_file"
fi

qdrant_curl() {
  if [ -s "$headers_file" ]; then
    curl --fail --silent --show-error -H "@$headers_file" "$@"
  else
    curl --fail --silent --show-error "$@"
  fi
}

collections="$(qdrant_curl "$QDRANT_URL/collections" | jq -r '.result.collections[].name')"
: > "$manifest"

if [ -z "$collections" ]; then
  echo "No Qdrant collections exist; wrote an empty manifest."
  exit 0
fi

printf '%s\n' "$collections" | while IFS= read -r collection; do
  case "$collection" in
    ""|*/*|*".."*) echo "Unsafe Qdrant collection name: $collection" >&2; exit 1 ;;
  esac

  details="$(qdrant_curl "$QDRANT_URL/collections/$collection")"
  points_count="$(printf '%s' "$details" | jq -r '.result.points_count // 0')"
  snapshot="$(
    qdrant_curl -X POST "$QDRANT_URL/collections/$collection/snapshots" |
      jq -er '.result.name'
  )"
  output="$BACKUP_DIR/qdrant/${collection}-${stamp}.snapshot"
  qdrant_curl \
    "$QDRANT_URL/collections/$collection/snapshots/$snapshot" \
    --output "$output"
  test -s "$output"

  jq -nc \
    --arg collection "$collection" \
    --arg file "$(basename "$output")" \
    --arg snapshot "$snapshot" \
    --argjson points_count "$points_count" \
    '{collection:$collection,file:$file,snapshot:$snapshot,points_count:$points_count}' \
    >> "$manifest"
done

echo "Created Qdrant collection snapshots in $BACKUP_DIR/qdrant"
