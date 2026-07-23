#!/bin/sh
# ====================================================================
# WarpTalk — Apply pending migrations, in true chronological order
#
# Filenames are NNN-DD-MM-YYYY-description.sql. The leading number is NOT
# a reliable sort key by itself: several files share the same number
# (e.g. 007-16-05-2026 and 007-03-06-2026), so plain alphabetical sort
# (`*.sql`, `ls | sort`) gets those pairs backwards. This script sorts by
# the DD-MM-YYYY embedded in each filename instead. Idempotent: applied
# files are tracked in public.schema_migrations, so re-running only picks
# up new ones — safe to call on every `docker compose up` / CI run.
#
# Run standalone (outside Docker) with:
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=*** PGDATABASE=warptalk \
#     ./scripts/run-migrations.sh
# ====================================================================
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$SCRIPT_DIR/migrations}"

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-warptalk}"
export PGPASSWORD="${PGPASSWORD:-}"

psql_exec() {
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}

if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "No migrations directory at $MIGRATIONS_DIR — nothing to do."
  exit 0
fi

echo "Waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."
i=0
until psql_exec -c "SELECT 1" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "PostgreSQL did not become ready in time." >&2
    exit 1
  fi
  sleep 1
done
echo "PostgreSQL is ready."

# The tracking table itself must exist before we can check what's applied.
# SQL is piped through `tr -d '\r'` so a CRLF-committed file (e.g. checked
# out on Windows) still applies cleanly, regardless of line endings.
if [ -f "$MIGRATIONS_DIR/000-init-migrations.sql" ]; then
  tr -d '\r' < "$MIGRATIONS_DIR/000-init-migrations.sql" | psql_exec -q >/dev/null
fi

TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT INT TERM

for path in "$MIGRATIONS_DIR"/*.sql; do
  [ -f "$path" ] || continue
  filename="$(basename "$path")"
  [ "$filename" = "000-init-migrations.sql" ] && continue

  dd=$(echo "$filename" | cut -d'-' -f2)
  mm=$(echo "$filename" | cut -d'-' -f3)
  yyyy=$(echo "$filename" | cut -d'-' -f4)

  if echo "$dd" | grep -qE '^[0-9]{2}$' \
    && echo "$mm" | grep -qE '^[0-9]{2}$' \
    && echo "$yyyy" | grep -qE '^[0-9]{4}$'; then
    sortkey="${yyyy}${mm}${dd}"
  else
    # Doesn't match the NNN-DD-MM-YYYY-*.sql pattern — sort last rather than
    # silently skip it, so an oddly named file still gets applied (and seen).
    sortkey="99999999"
  fi

  printf '%s\t%s\n' "$sortkey" "$filename" >> "$TMP_LIST"
done

sort "$TMP_LIST" | while IFS="$(printf '\t')" read -r _sortkey filename; do
  already_applied=$(psql_exec -tAc \
    "SELECT 1 FROM public.schema_migrations WHERE version='$filename';" 2>/dev/null || true)

  if [ "$already_applied" = "1" ]; then
    echo "  Skipping $filename (already applied)"
    continue
  fi

  echo "  Applying $filename..."
  tr -d '\r' < "$MIGRATIONS_DIR/$filename" | psql_exec
  psql_exec -q -c "INSERT INTO public.schema_migrations(version) VALUES ('$filename');"
done

echo "Migrations complete."
