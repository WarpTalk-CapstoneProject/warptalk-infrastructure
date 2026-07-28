#!/bin/sh
# Extract each bounded-context schema from the shared database into a logical
# PostgreSQL database. Run inside the postgres image (the migrator service is
# the supported entry point):
#
#   docker compose run --rm --no-deps --entrypoint sh migrator \
#     /scripts/extract-logical-databases.sh
#
# The operation is intentionally non-destructive. Existing target databases are
# never overwritten; rerun only after a verified backup and explicit removal.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

command -v psql >/dev/null 2>&1 || { echo "psql is required" >&2; exit 1; }
command -v pg_dump >/dev/null 2>&1 || { echo "pg_dump is required" >&2; exit 1; }

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

psql_admin() {
    psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}

database_exists() {
    target="$1"
    psql_admin -Atc "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$target')"
}

create_database() {
    target="$1"
    psql_admin >/dev/null <<SQL
SELECT format('CREATE DATABASE %I', '$target')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$target')
\gexec
SQL
}

run_target() {
    target="$1"
    shift
    PGPASSWORD="$PGPASSWORD" psql -X -v ON_ERROR_STOP=1 \
        -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$target" "$@"
}

extract_context() {
    target="$1"
    schemas="$2"
    login="$3"
    runtime_role="$4"
    if [ "$(database_exists "$target")" = "t" ]; then
        if [ "$(run_target "$target" -Atc "SELECT to_regclass('public.logical_database_extract') IS NOT NULL")" = "t" ]; then
            echo "Skipping existing logical database $target (already extracted)."
            return
        fi
        echo "Logical database $target exists without an extraction marker; refusing to overwrite a partial or unknown database." >&2
        exit 1
    fi

    create_database "$target"
    schema_dump="$tmp_dir/$target-schema.sql"
    data_dump="$tmp_dir/$target-data.sql"

    dump_args=""
    for schema in $schemas; do
        dump_args="$dump_args --schema=$schema"
    done

    # Keep public extensions/types and schema migration metadata with each
    # logical database, then copy only the bounded-context data.
    pg_dump --format=plain --no-owner --no-acl --schema-only \
        -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        $dump_args | sed '/^CREATE SCHEMA public;$/d' > "$schema_dump"
    # data_dump_args intentionally expands into multiple --schema arguments.
    # shellcheck disable=SC2046
    pg_dump --format=plain --no-owner --no-acl --data-only --disable-triggers \
        -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        $(for schema in $schemas; do [ "$schema" = "public" ] || printf '%s ' "--schema=$schema"; done) \
        > "$data_dump"

    run_target "$target" -f "$schema_dump"
    run_target "$target" -f "$data_dump"

    run_target "$target" <<SQL
REVOKE CONNECT ON DATABASE "$target" FROM PUBLIC;
GRANT CONNECT ON DATABASE "$target" TO "$login";
GRANT USAGE ON SCHEMA $(
    printf '%s,' $schemas | sed 's/,$//'
) TO "$runtime_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA $(
    printf '%s,' $schemas | sed 's/,$//'
) TO "$runtime_role";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA $(
    printf '%s,' $schemas | sed 's/,$//'
) TO "$runtime_role";
CREATE TABLE public.logical_database_extract (
    source_database TEXT NOT NULL,
    owned_schemas TEXT[] NOT NULL,
    extracted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.logical_database_extract (source_database, owned_schemas)
VALUES ('$PGDATABASE', ARRAY[$(printf "'%s'," $schemas | sed "s/,$//")]);
SQL
    echo "Extracted $target ($schemas)."
}

# public is included so PostgreSQL extensions, UUID helpers, enum types and the
# migration metadata remain available to the bounded-context schema.
extract_context warptalk_auth "public auth voice" warptalk_auth warptalk_auth_runtime
extract_context warptalk_workspace "public workspace" warptalk_workspace warptalk_workspace_runtime
extract_context warptalk_translation_room "public translation_room" warptalk_translation_room warptalk_translation_room_runtime
extract_context warptalk_transcript "public transcript" warptalk_transcript warptalk_transcript_runtime
extract_context warptalk_notification "public notification" warptalk_notification warptalk_notification_runtime
extract_context warptalk_meeting "public meeting" warptalk_meeting warptalk_meeting_runtime
extract_context warptalk_assistant "public assistant" warptalk_assistant warptalk_assistant_runtime
extract_context warptalk_billing "public subscription" warptalk_billing warptalk_billing_runtime

echo "Logical database extraction complete."
