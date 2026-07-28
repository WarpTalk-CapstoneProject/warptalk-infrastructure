#!/bin/sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

test_database="warptalk_migration_test_$$"
case "$test_database" in
  warptalk_migration_test_[0-9]*) ;;
  *) echo "Unsafe test database name: $test_database" >&2; exit 1 ;;
esac

fixture_root="$(mktemp -d)"
runner="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)/run-logical-database-migrations.sh"

admin_psql() {
  PGPASSWORD="$PGPASSWORD" psql -X -v ON_ERROR_STOP=1 \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "${PGDATABASE:-warptalk}" "$@"
}

test_psql() {
  PGPASSWORD="$PGPASSWORD" psql -X -v ON_ERROR_STOP=1 \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$test_database" "$@"
}

cleanup() {
  admin_psql -c "DROP DATABASE IF EXISTS \"$test_database\" WITH (FORCE);" >/dev/null
  rm -rf "$fixture_root"
}
trap cleanup EXIT INT TERM

admin_psql -c "CREATE DATABASE \"$test_database\";" >/dev/null
mkdir -p "$fixture_root/auth"

cat > "$fixture_root/auth/001_empty_state.sql" <<'SQL'
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.migration_probe (
  id integer PRIMARY KEY,
  value text NOT NULL
);
INSERT INTO auth.migration_probe(id, value) VALUES (1, 'empty-state');
SQL

run_migrations() {
  SERVICE_MIGRATIONS_ROOT="$fixture_root" \
  AUTH_DATABASE="$test_database" \
  RELEASE_ID="migration-framework-test" \
  MIGRATION_APPLIED_BY="test-runner" \
  "$runner"
}

run_migrations >/dev/null
run_migrations >/dev/null

[ "$(test_psql -Atc "SELECT count(*) FROM public.service_schema_migrations")" = "1" ]
[ "$(test_psql -Atc "SELECT count(*) FROM auth.migration_probe")" = "1" ]

cat > "$fixture_root/auth/002_n_minus_one_upgrade.sql" <<'SQL'
ALTER TABLE auth.migration_probe ADD COLUMN upgraded_at timestamptz;
UPDATE auth.migration_probe SET upgraded_at = now();
SQL

run_migrations >/dev/null &
first_pid=$!
run_migrations >/dev/null &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

[ "$(test_psql -Atc "SELECT count(*) FROM public.service_schema_migrations")" = "2" ]
[ "$(test_psql -Atc "SELECT count(*) FROM information_schema.columns WHERE table_schema='auth' AND table_name='migration_probe' AND column_name='upgraded_at'")" = "1" ]
[ "$(test_psql -Atc "SELECT count(*) FROM public.service_schema_migrations WHERE checksum IS NOT NULL AND execution_ms IS NOT NULL AND release='migration-framework-test' AND applied_by='test-runner'")" = "2" ]

cat > "$fixture_root/auth/003_transaction_rollback.sql" <<'SQL'
CREATE TABLE auth.must_rollback (id integer PRIMARY KEY);
SELECT definitely_missing_function();
SQL

if run_migrations >/dev/null 2>&1; then
  echo "Expected the invalid migration to fail." >&2
  exit 1
fi

[ "$(test_psql -Atc "SELECT to_regclass('auth.must_rollback') IS NULL")" = "t" ]
[ "$(test_psql -Atc "SELECT count(*) FROM public.service_schema_migrations WHERE version='003_transaction_rollback.sql'")" = "0" ]
rm -f "$fixture_root/auth/003_transaction_rollback.sql"

printf '\n-- checksum drift\n' >> "$fixture_root/auth/002_n_minus_one_upgrade.sql"
checksum_output="$(run_migrations 2>&1)" && checksum_status=0 || checksum_status=$?
if [ "$checksum_status" -eq 0 ]; then
  echo "Expected checksum drift to fail." >&2
  printf '%s\n' "$checksum_output" >&2
  exit 1
fi

echo "Logical-database migration framework tests passed."
