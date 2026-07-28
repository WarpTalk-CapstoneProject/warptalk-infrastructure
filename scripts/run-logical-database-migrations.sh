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

configure_migration_owner() {
  database="$1"
  schema="$2"
  runtime_role="$3"

  PGPASSWORD="$PGPASSWORD" psql \
    -X \
    -v ON_ERROR_STOP=1 \
    -v "schema_name=$schema" \
    -v "runtime_role=$runtime_role" \
    -h "$PGHOST" \
    -p "$PGPORT" \
    -U "$PGUSER" \
    -d "$database" <<'SQL'
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
  dir="$ROOT/$service"
  [ -d "$dir" ] || return 0
  [ "$(database_exists "$database")" = "t" ] || {
    echo "Skipping $service: $database does not exist yet."
    return 0
  }
  configure_migration_owner "$database" "$schema" "$runtime_role"
  files="$(find "$dir" -maxdepth 1 -type f -name '*.sql' -print | sort)"
  [ -n "$files" ] || return 0

  echo "Applying logical-database migrations for $service ($database)..."
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT INT TERM
  {
    echo '\set ON_ERROR_STOP on'
    printf "CREATE TABLE IF NOT EXISTS public.service_schema_migrations (service text NOT NULL, version text NOT NULL, checksum text, execution_ms bigint, release text, applied_by text, applied_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(service, version));\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS checksum text;\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS execution_ms bigint;\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS release text;\n"
    printf "ALTER TABLE public.service_schema_migrations ADD COLUMN IF NOT EXISTS applied_by text;\n"
    printf "SELECT pg_advisory_lock(hashtext('warptalk-service-migrations:%s'));\n" "$service"
    printf "SET search_path TO %s, public;\n" "$schema"
    printf '%s\n' "$files" | while IFS= read -r path; do
      filename="$(basename "$path")"
      escaped="$(sql_literal "$filename")"
      checksum="$(file_checksum "$path")"
      escaped_release="$(sql_literal "$RELEASE_ID")"
      escaped_applied_by="$(sql_literal "$MIGRATION_APPLIED_BY")"
      printf "SELECT EXISTS (SELECT 1 FROM public.service_schema_migrations WHERE service='%s' AND version='%s') AS applied, COALESCE((SELECT checksum FROM public.service_schema_migrations WHERE service='%s' AND version='%s'), '') AS applied_checksum \\gset\n" "$service" "$escaped" "$service" "$escaped"
      echo '\if :applied'
      printf "SELECT :'applied_checksum' = '%s' AS checksum_matches \\gset\n" "$checksum"
      echo '\if :checksum_matches'
      printf '%s\n' "\\echo '  Skipping $filename (already applied, checksum verified)'"
      echo '\else'
      printf '%s\n' "\\echo 'ERROR: checksum mismatch for $filename'"
      echo 'SELECT 1 / 0;'
      echo '\endif'
      echo '\else'
      printf '%s\n' "\\echo '  Applying $filename...'"
      echo 'SELECT clock_timestamp() AS migration_started_at \gset'
      echo 'BEGIN;'
      echo 'SET LOCAL ROLE warptalk_migrator;'
      printf "SET LOCAL search_path TO %s, public;\n" "$schema"
      printf '%s\n' "\\ir '$path'"
      echo 'RESET ROLE;'
      printf "INSERT INTO public.service_schema_migrations(service, version, checksum, execution_ms, release, applied_by) VALUES ('%s','%s','%s', GREATEST(0, ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - :'migration_started_at'::timestamptz)) * 1000)::bigint), '%s', '%s');\n" "$service" "$escaped" "$checksum" "$escaped_release" "$escaped_applied_by"
      echo 'COMMIT;'
      echo '\endif'
    done
    printf "SELECT pg_advisory_unlock(hashtext('warptalk-service-migrations:%s'));\n" "$service"
  } > "$tmp"
  if ! PGPASSWORD="$PGPASSWORD" psql -X -v ON_ERROR_STOP=1 \
      -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" -f "$tmp"; then
    rm -f "$tmp"
    trap - EXIT INT TERM
    return 1
  fi
  rm -f "$tmp"
  trap - EXIT INT TERM
}

apply_service auth "${AUTH_DATABASE:-warptalk_auth}" auth warptalk_auth_runtime
apply_service workspace "${WORKSPACE_DATABASE:-warptalk_workspace}" workspace warptalk_workspace_runtime
apply_service translation-room "${TRANSLATION_ROOM_DATABASE:-warptalk_translation_room}" translation_room warptalk_translation_room_runtime
apply_service transcript "${TRANSCRIPT_DATABASE:-warptalk_transcript}" transcript warptalk_transcript_runtime
apply_service notification "${NOTIFICATION_DATABASE:-warptalk_notification}" notification warptalk_notification_runtime
apply_service meeting "${MEETING_DATABASE:-warptalk_meeting}" meeting warptalk_meeting_runtime
apply_service assistant "${ASSISTANT_DATABASE:-warptalk_assistant}" assistant warptalk_assistant_runtime
apply_service billing "${BILLING_DATABASE:-warptalk_billing}" subscription warptalk_billing_runtime

echo "Logical-database migrations complete."
