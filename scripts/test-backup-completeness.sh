#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
fixture_bin="$script_dir/test-fixtures/backup-bin"
backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-backup-test.XXXXXX")"
trap 'rm -rf "$backup_dir"' EXIT INT TERM

if PATH="$fixture_bin:$PATH" \
  PGHOST=postgres \
  PGPORT=5432 \
  PGUSER=backup \
  PGPASSWORD=test-only \
  BACKUP_DIR="$backup_dir" \
  FAIL_DATABASE=warptalk_translation_room \
  "$script_dir/backup-logical-databases.sh"; then
  echo "backup script reported success after pg_dump failed" >&2
  exit 1
fi

echo "backup completeness failure contract passed"
