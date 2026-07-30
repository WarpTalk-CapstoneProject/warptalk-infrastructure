#!/bin/sh
# Create independent compressed backups for every bounded-context database.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${BACKUP_DIR:?BACKUP_DIR is required}"

command -v pg_dump >/dev/null 2>&1 || { echo "pg_dump is required" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
manifest="$BACKUP_DIR/manifest-$stamp.sha256"
database_manifest="$BACKUP_DIR/manifest-$stamp.txt"
: > "$database_manifest"

for database in \
  warptalk_auth \
  warptalk_workspace \
  warptalk_translation_room \
  warptalk_transcript \
  warptalk_notification \
  warptalk_meeting \
  warptalk_assistant \
  warptalk_billing; do
  output="$BACKUP_DIR/${database}-${stamp}.dump"
  pg_dump --format=custom --compress=6 --no-owner --no-acl \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" -f "$output"
  printf '%s  %s\n' "$database" "$output" | tee -a "$database_manifest"
done

dump_count="$(
  find "$BACKUP_DIR" -maxdepth 1 -type f -name "*-$stamp.dump" |
    wc -l |
    tr -d ' '
)"
[ "$dump_count" -eq 8 ] || {
  echo "Expected 8 logical database dumps, found $dump_count" >&2
  exit 1
}

(
  cd "$BACKUP_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum ./*-"$stamp".dump
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 ./*-"$stamp".dump
  else
    echo "sha256sum or shasum is required" >&2
    exit 1
  fi
) > "$manifest"
echo "Created independent logical database backups in $BACKUP_DIR"
