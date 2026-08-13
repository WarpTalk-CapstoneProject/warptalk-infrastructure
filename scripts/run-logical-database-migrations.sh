#!/bin/sh
# Apply post-extraction migrations from service-owned directories.
#
# Historical migrations run once against the shared source database. From the
# logical-database cutover onward, every new migration belongs to exactly one
# service directory and is applied to that service database only.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

ROOT="${SERVICE_MIGRATIONS_ROOT:-/scripts/service-migrations}"
RELEASE_ID="${RELEASE_ID:-local}"
MIGRATION_APPLIED_BY="${MIGRATION_APPLIED_BY:-${PGUSER}@$(hostname)}"
UNSTAGED_SERVICES=""

sql_literal() {
  printf '%s' "$1" | sed "s/'/''/g"
}

file_checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

admin_psql() {
  psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "${PGDATABASE:-warptalk}" "$@"
}

database_exists() {
  admin_psql -Atc "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$1')"
}

emit_migration_owner_sql() {
  owned_schema="$1"
  # The body below is written against :"schema_name". A service can own more than one schema
  # (auth owns `auth` AND `voice`), so this is emitted once per owned schema with the variable
  # re-pointed each time, rather than once for the service's namesake schema only.
  printf '\\set schema_name %s\n' "$owned_schema"
  cat <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_migrator'
    ) THEN
        CREATE ROLE warptalk_migrator
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
    END IF;
END
$$;

SELECT format(
    'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
    :'runtime_role')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'runtime_role'
)
\gexec

CREATE SCHEMA IF NOT EXISTS :"schema_name";
ALTER SCHEMA :"schema_name" OWNER TO warptalk_migrator;
GRANT USAGE, CREATE ON SCHEMA :"schema_name" TO warptalk_migrator;

-- Logical databases extracted before the stable migration role existed have
-- bootstrap-owned objects. Transfer only objects inside the service schema so
-- later migrations can alter indexes/tables without superuser execution.
SELECT set_config('warptalk.migration_schema', :'schema_name', false);
DO $ownership$
DECLARE
    object_record record;
BEGIN
    FOR object_record IN
        SELECT c.relkind, n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_setting('warptalk.migration_schema')
          AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
        ORDER BY CASE WHEN c.relkind IN ('r', 'p') THEN 0 ELSE 1 END
    LOOP
        EXECUTE CASE object_record.relkind
            WHEN 'S' THEN format(
                'ALTER SEQUENCE %I.%I OWNER TO warptalk_migrator',
                object_record.nspname,
                object_record.relname)
            WHEN 'v' THEN format(
                'ALTER VIEW %I.%I OWNER TO warptalk_migrator',
                object_record.nspname,
                object_record.relname)
            WHEN 'm' THEN format(
                'ALTER MATERIALIZED VIEW %I.%I OWNER TO warptalk_migrator',
                object_record.nspname,
                object_record.relname)
            ELSE format(
                'ALTER TABLE %I.%I OWNER TO warptalk_migrator',
                object_record.nspname,
                object_record.relname)
        END;
    END LOOP;

    -- WT-294: routines were never included in the transfer above, so a function
    -- created by the pre-extraction bootstrap stayed owned by the superuser and
    -- warptalk_migrator could neither CREATE OR REPLACE nor DROP it —
    -- "must be owner of function ...", which aborts the whole service's chain.
    -- BillingService is the only schema with routines today
    -- (subscription.resolve_contract_terms, .settle_usage_charge and friends,
    -- from 041-26-07-2026-phase3-contract-overage-settlement.sql), and that is
    -- exactly the set its own migrations 004 and 017 have to replace.
    FOR object_record IN
        SELECT p.oid, p.prokind
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = current_setting('warptalk.migration_schema')
    LOOP
        EXECUTE format(
            'ALTER %s %s OWNER TO warptalk_migrator',
            CASE object_record.prokind
                WHEN 'p' THEN 'PROCEDURE'
                WHEN 'a' THEN 'AGGREGATE'
                ELSE 'FUNCTION'
            END,
            object_record.oid::regprocedure);
    END LOOP;
END
$ownership$;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA :"schema_name"
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA :"schema_name"
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"runtime_role";
SQL
}

apply_service() {
  service="$1"
  database="$2"
  schema="$3"
  runtime_role="$4"
  # Schemas this logical database owns BEYOND its namesake, space separated.
  #
  # WHY THIS EXISTS
  #   extract-logical-databases.sh puts `public auth voice` into warptalk_auth, so AuthService
  #   owns two schemas — but ownership was only ever transferred for the one named here, which
  #   left `voice` owned by the bootstrap superuser and therefore UNMIGRATABLE. The failure is
  #   not subtle when you hit it ("permission denied for schema voice") but it is invisible
  #   until someone writes the first migration that touches it, which is what happened to
  #   voice.voice_consents. test-database-boundary-isolation.sh pins this list against the
  #   extractor's own dispatch table so the two cannot drift.
  extra_schemas="${5:-}"
  dir="$ROOT/$service"
  # WT-294: a missing directory used to be skipped in total silence, which is
  # how transcript, notification, meeting and assistant went from the logical
  # cutover to 2026-08 without a single migration and without a single log line
  # saying so. Record it and report it at the end. collect-service-migrations.sh
  # now stages a .gitkeep for empty sets, so an absent directory in a release
  # bundle means the bundle is wrong, not that the service has nothing to apply.
  [ -d "$dir" ] || {
    UNSTAGED_SERVICES="${UNSTAGED_SERVICES}${UNSTAGED_SERVICES:+, }$service ($database)"
    return 0
  }
  [ "$(database_exists "$database")" = "t" ] || {
    echo "Skipping $service: $database does not exist yet."
    return 0
  }
  files="$(find "$dir" -maxdepth 1 -type f -name '*.sql' -print | sort)"
  [ -n "$files" ] || {
    echo "No migrations staged for $service; $database is unchanged."
    return 0
  }

  echo "Applying logical-database migrations for $service ($database)..."
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT INT TERM
  {
    printf '%s\n' '\set ON_ERROR_STOP on'
    printf "SELECT pg_advisory_lock(hashtext('warptalk-service-migrations:%s'));\n" "$service"
    for owned in $schema $extra_schemas; do
      emit_migration_owner_sql "$owned"
    done
    # Restore the variable the rest of the file reads, so a service with extra schemas still
    # runs its migrations under its OWN schema's search_path and not the last one owned.
    printf '\\set schema_name %s\n' "$schema"
    printf "CREATE TABLE IF NOT EXISTS public.service_schema_migrations (service text NOT NULL, version text NOT NULL, checksum text, execution_ms bigint, release text, applied_by text, applied_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(service, version));\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS checksum text;\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS execution_ms bigint;\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS release text;\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS applied_by text;\n"
    printf "SET search_path TO %s, public;\n" "$schema"
    printf '%s\n' "$files" | while IFS= read -r path; do
      filename="$(basename "$path")"
      escaped="$(sql_literal "$filename")"
      checksum="$(file_checksum "$path")"
      escaped_release="$(sql_literal "$RELEASE_ID")"
      escaped_applied_by="$(sql_literal "$MIGRATION_APPLIED_BY")"
      printf "SELECT EXISTS (SELECT 1 FROM public.service_schema_migrations WHERE service='%s' AND version='%s') AS applied, COALESCE((SELECT checksum FROM public.service_schema_migrations WHERE service='%s' AND version='%s'), '') AS applied_checksum \\gset\n" "$service" "$escaped" "$service" "$escaped"
      printf "SELECT 1 / (NOT (:'applied'::boolean AND :'applied_checksum' <> '%s'))::integer;\n" "$checksum"
      printf '%s\n' '\if :applied'
      printf '%s\n' "\\echo '  Skipping $filename (already applied, checksum verified)'"
      printf '%s\n' '\else'
      printf '%s\n' "\\echo '  Applying $filename...'"
      echo 'SELECT clock_timestamp() AS migration_started_at \gset'
      echo 'BEGIN;'
      echo 'SET LOCAL ROLE warptalk_migrator;'
      printf "SET LOCAL search_path TO %s, public;\n" "$schema"
      printf '%s\n' "\\ir '$path'"
      echo 'RESET ROLE;'
      printf "INSERT INTO public.service_schema_migrations(service, version, checksum, execution_ms, release, applied_by) VALUES ('%s','%s','%s', GREATEST(0, ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - :'migration_started_at'::timestamptz)) * 1000)::bigint), '%s', '%s');\n" "$service" "$escaped" "$checksum" "$escaped_release" "$escaped_applied_by"
      echo 'COMMIT;'
      printf '%s\n' '\endif'
    done
    printf "SELECT pg_advisory_unlock(hashtext('warptalk-service-migrations:%s'));\n" "$service"
  } > "$tmp"
  if ! PGPASSWORD="$PGPASSWORD" psql -X -v ON_ERROR_STOP=1 \
      -v "schema_name=$schema" \
      -v "runtime_role=$runtime_role" \
      -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" -f "$tmp"; then
    rm -f "$tmp"
    trap - EXIT INT TERM
    return 1
  fi
  rm -f "$tmp"
  trap - EXIT INT TERM
}

apply_service auth "${AUTH_DATABASE:-warptalk_auth}" auth warptalk_auth_runtime "voice"
apply_service workspace "${WORKSPACE_DATABASE:-warptalk_workspace}" workspace warptalk_workspace_runtime
apply_service translation-room "${TRANSLATION_ROOM_DATABASE:-warptalk_translation_room}" translation_room warptalk_translation_room_runtime
apply_service transcript "${TRANSCRIPT_DATABASE:-warptalk_transcript}" transcript warptalk_transcript_runtime
apply_service notification "${NOTIFICATION_DATABASE:-warptalk_notification}" notification warptalk_notification_runtime
apply_service meeting "${MEETING_DATABASE:-warptalk_meeting}" meeting warptalk_meeting_runtime
apply_service assistant "${ASSISTANT_DATABASE:-warptalk_assistant}" assistant warptalk_assistant_runtime
apply_service billing "${BILLING_DATABASE:-warptalk_billing}" subscription warptalk_billing_runtime

[ -z "$UNSTAGED_SERVICES" ] || \
  echo "WARNING: no migration set staged for: ${UNSTAGED_SERVICES}. Those databases received nothing." >&2

echo "Logical-database migrations complete."
