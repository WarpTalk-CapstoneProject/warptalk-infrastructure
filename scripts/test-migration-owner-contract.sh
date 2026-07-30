#!/bin/sh
set -eu

root_dir="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
runtime_migrations="$root_dir/scripts/migrations"
logical_runner="$root_dir/scripts/run-logical-database-migrations.sh"

files="$(
  grep -l "ALTER DEFAULT PRIVILEGES" "$runtime_migrations"/*.sql |
    sort
)"
[ -n "$files" ]

printf '%s\n' "$files" | while IFS= read -r migration; do
  if grep -q "ALTER DEFAULT PRIVILEGES IN SCHEMA" "$migration"; then
    echo "$migration contains owner-dependent default privileges" >&2
    exit 1
  fi
  grep -q "ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA" "$migration"
done

grep -q "CREATE ROLE warptalk_migrator" \
  "$runtime_migrations/032-27-07-2026-add-billing-runtime-role.sql"
grep -q "SET LOCAL ROLE warptalk_migrator" "$logical_runner"
grep -q "RESET ROLE" "$logical_runner"
grep -q "configure_migration_owner" "$logical_runner"
grep -q "ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator" "$logical_runner"

echo "migration owner contract passed"
