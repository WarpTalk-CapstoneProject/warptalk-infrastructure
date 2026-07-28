#!/bin/sh
# Acceptance checks for the extracted per-service PostgreSQL databases.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

check_mode="${LOGICAL_DATABASE_CHECK_MODE:-cutover}"
case "$check_mode" in
  cutover|runtime) ;;
  *) echo "LOGICAL_DATABASE_CHECK_MODE must be cutover or runtime" >&2; exit 1 ;;
esac

psql_admin() {
  psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}

database_psql() {
  database="$1"
  shift
  PGPASSWORD="$PGPASSWORD" psql -X -v ON_ERROR_STOP=1 \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" "$@"
}

target_count() {
  db="$1"; schema="$2"; table="$3"
  database_psql "$db" -Atc \
    "SELECT count(*) FROM \"$schema\".\"$table\""
}

check_context() {
  target="$1"; login="$2"; schemas="$3"
  marker="$(database_psql "$target" -Atc \
    "SELECT source_database || ':' || array_to_string(owned_schemas, ',') FROM public.logical_database_extract")"
  [ -n "$marker" ] || { echo "FAIL $target: extraction marker missing" >&2; exit 1; }

  connect="$(psql_admin -Atc "SELECT has_database_privilege('$login', '$target', 'CONNECT')")"
  [ "$connect" = "t" ] || { echo "FAIL $target: $login lacks CONNECT" >&2; exit 1; }

  for schema in $schemas; do
    tables="$(database_psql "$target" -AtF '|' -c \
      "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema = '$schema' AND table_type = 'BASE TABLE' ORDER BY 1,2")"
    [ -n "$tables" ] || {
      echo "FAIL $target: owned schema $schema has no base tables" >&2
      exit 1
    }
    while IFS='|' read -r table_schema table_name; do
      [ -n "$table_name" ] || continue
      if [ "$check_mode" = "cutover" ]; then
        source_rows="$(target_count "$PGDATABASE" "$table_schema" "$table_name")"
        target_rows="$(target_count "$target" "$table_schema" "$table_name")"
        [ "$source_rows" = "$target_rows" ] || {
          echo "FAIL $target: $table_schema.$table_name row count $target_rows != source $source_rows" >&2
          exit 1
        }
      else
        qualified_table="\"$table_schema\".\"$table_name\""
        privileges="$(database_psql "$target" -Atc \
          "SELECT has_table_privilege('$login', '$qualified_table', 'SELECT,INSERT,UPDATE,DELETE')")"
        [ "$privileges" = "t" ] || {
          echo "FAIL $target: $login lacks DML on $table_schema.$table_name" >&2
          exit 1
        }
      fi
    done <<EOF
$tables
EOF
  done
  echo "PASS $target marker/connect/$check_mode"
}

check_context warptalk_auth warptalk_auth "auth voice"
check_context warptalk_workspace warptalk_workspace "workspace"
check_context warptalk_translation_room warptalk_translation_room "translation_room"
check_context warptalk_transcript warptalk_transcript "transcript"
check_context warptalk_notification warptalk_notification "notification"
check_context warptalk_meeting warptalk_meeting "meeting"
check_context warptalk_assistant warptalk_assistant "assistant"
check_context warptalk_billing warptalk_billing "subscription"

targets="warptalk_auth warptalk_workspace warptalk_translation_room warptalk_transcript warptalk_notification warptalk_meeting warptalk_assistant warptalk_billing"
for pair in \
  "warptalk_auth:warptalk_auth" \
  "warptalk_workspace:warptalk_workspace" \
  "warptalk_translation_room:warptalk_translation_room" \
  "warptalk_transcript:warptalk_transcript" \
  "warptalk_notification:warptalk_notification" \
  "warptalk_meeting:warptalk_meeting" \
  "warptalk_assistant:warptalk_assistant" \
  "warptalk_billing:warptalk_billing"; do
  login="${pair%%:*}"
  own_db="${pair##*:}"
  for target in $targets; do
    [ "$target" = "$own_db" ] && continue
    denied="$(psql_admin -Atc "SELECT has_database_privilege('$login', '$target', 'CONNECT')")"
    [ "$denied" = "f" ] || {
      echo "FAIL $login unexpectedly has CONNECT on $target" >&2
      exit 1
    }
  done
done

echo "Logical database $check_mode acceptance checks passed."
