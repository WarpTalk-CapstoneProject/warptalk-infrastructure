#!/usr/bin/env sh
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

DATABASES="${WARPTALK_DATABASES:-warptalk_auth warptalk_workspace warptalk_translation_room warptalk_transcript warptalk_notification warptalk_meeting warptalk_billing warptalk_assistant}"

for database in $DATABASES; do
  echo "enabling pg_stat_statements in $database"
  PGDATABASE="$database" psql -X -v ON_ERROR_STOP=1 \
    -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" >/dev/null
done

PGDATABASE=warptalk_billing psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
GRANT CONNECT ON DATABASE warptalk_billing TO warptalk_monitor;
GRANT USAGE ON SCHEMA subscription TO warptalk_monitor;
GRANT SELECT ON subscription.usage_records TO warptalk_monitor;
SQL

PGDATABASE=warptalk_translation_room psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
GRANT CONNECT ON DATABASE warptalk_translation_room TO warptalk_monitor;
GRANT USAGE ON SCHEMA translation_room TO warptalk_monitor;
GRANT SELECT ON
  translation_room.translation_rooms,
  translation_room.translation_room_artifacts
TO warptalk_monitor;
SQL

PGDATABASE=warptalk_workspace psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
GRANT CONNECT ON DATABASE warptalk_workspace TO warptalk_monitor;
GRANT USAGE ON SCHEMA workspace TO warptalk_monitor;
GRANT SELECT ON workspace.workspace_documents TO warptalk_monitor;
SQL

echo "PostgreSQL performance observability enabled for all logical databases."
