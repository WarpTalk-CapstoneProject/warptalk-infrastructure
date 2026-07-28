#!/bin/sh
# Complete, idempotent database release gate for a fresh or upgraded K3s
# deployment. Keep this sequence aligned with the production Compose migrator.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"

export MIGRATIONS_DIR="${MIGRATIONS_DIR:-/scripts/migrations}"
export SERVICE_MIGRATIONS_ROOT="${SERVICE_MIGRATIONS_ROOT:-/scripts/service-migrations}"
export RELEASE_ID="${RELEASE_ID:-k3s-release}"
export MIGRATION_APPLIED_BY="${MIGRATION_APPLIED_BY:-k3s-migrator}"

/scripts/run-migrations.sh
/scripts/provision-service-db-users.sh
/scripts/extract-logical-databases.sh
/scripts/run-logical-database-migrations.sh
exec /scripts/enable-postgres-performance-observability.sh
