#!/bin/sh
# Validate service-schema isolation using PostgreSQL's effective privileges.
# Run with the same administrator PG* variables used by the migrator.
set -eu

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-warptalk}"
: "${PGPASSWORD:?PGPASSWORD is required}"
export PGPASSWORD

psql \
  -X \
  -v ON_ERROR_STOP=1 \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" <<'SQL'
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint constraint_definition
        JOIN pg_class source_table
            ON source_table.oid = constraint_definition.conrelid
        JOIN pg_namespace source_schema
            ON source_schema.oid = source_table.relnamespace
        JOIN pg_class target_table
            ON target_table.oid = constraint_definition.confrelid
        JOIN pg_namespace target_schema
            ON target_schema.oid = target_table.relnamespace
        WHERE constraint_definition.contype = 'f'
          AND source_schema.nspname <> target_schema.nspname
          AND source_schema.nspname NOT IN ('pg_catalog', 'information_schema')
    ) THEN
        RAISE EXCEPTION 'cross-schema foreign keys violate service database boundaries';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_views view_definition
        WHERE view_definition.schemaname IN (
            'auth', 'voice', 'workspace', 'translation_room', 'transcript',
            'notification', 'meeting', 'assistant', 'subscription'
        )
          AND EXISTS (
              SELECT 1
              FROM regexp_matches(
                  view_definition.definition,
                  '\m(auth|voice|workspace|translation_room|transcript|notification|meeting|assistant|subscription)\.',
                  'g'
              ) AS referenced_schema(schema_match)
              WHERE referenced_schema.schema_match[1]
                  <> view_definition.schemaname
          )
    ) THEN
        RAISE EXCEPTION 'cross-schema views violate service database boundaries';
    END IF;

    IF NOT has_schema_privilege('warptalk_billing', 'subscription', 'USAGE')
       OR NOT has_table_privilege(
           'warptalk_billing',
           'subscription.subscriptions',
           'SELECT,INSERT,UPDATE,DELETE'
       ) THEN
        RAISE EXCEPTION 'Billing runtime is missing subscription schema DML privileges';
    END IF;

    IF has_schema_privilege('warptalk_billing', 'workspace', 'USAGE')
       OR has_table_privilege(
           'warptalk_billing',
           'workspace.workspaces',
           'SELECT'
       ) THEN
        RAISE EXCEPTION 'Billing runtime can access Workspace-owned data';
    END IF;

    IF NOT has_schema_privilege('warptalk_workspace', 'workspace', 'USAGE')
       OR NOT has_table_privilege(
           'warptalk_workspace',
           'workspace.workspaces',
           'SELECT,INSERT,UPDATE,DELETE'
       ) THEN
        RAISE EXCEPTION 'Workspace runtime is missing workspace schema DML privileges';
    END IF;

    IF has_schema_privilege('warptalk_workspace', 'auth', 'USAGE')
       OR has_table_privilege('warptalk_workspace', 'auth.users', 'SELECT')
       OR has_schema_privilege('warptalk_workspace', 'subscription', 'USAGE')
       OR has_table_privilege(
           'warptalk_workspace',
           'subscription.subscriptions',
           'SELECT'
       ) THEN
        RAISE EXCEPTION 'Workspace runtime can access another service schema';
    END IF;

    IF NOT has_schema_privilege('warptalk_notification', 'notification', 'USAGE')
       OR NOT has_table_privilege(
           'warptalk_notification',
           'notification.notification_messages',
           'SELECT,INSERT,UPDATE,DELETE'
       ) THEN
        RAISE EXCEPTION 'Notification runtime is missing notification schema DML privileges';
    END IF;

    IF has_schema_privilege('warptalk_notification', 'subscription', 'USAGE')
       OR has_table_privilege(
           'warptalk_notification',
           'subscription.outbox_messages',
           'SELECT'
       )
       OR has_schema_privilege('warptalk_notification', 'workspace', 'USAGE')
       OR has_table_privilege(
           'warptalk_notification',
           'workspace.workspaces',
           'SELECT'
       ) THEN
        RAISE EXCEPTION 'Notification runtime can access a producer service schema';
    END IF;

    IF NOT has_schema_privilege('warptalk_auth', 'auth', 'USAGE')
       OR NOT has_table_privilege(
           'warptalk_auth',
           'auth.users',
           'SELECT,INSERT,UPDATE,DELETE'
       )
       OR NOT has_schema_privilege('warptalk_auth', 'voice', 'USAGE')
       OR NOT has_table_privilege(
           'warptalk_auth',
           'voice.voice_profiles',
           'SELECT,INSERT,UPDATE,DELETE'
       ) THEN
        RAISE EXCEPTION 'Auth runtime is missing identity or voice-profile DML privileges';
    END IF;

    IF has_schema_privilege('warptalk_auth', 'workspace', 'USAGE')
       OR has_table_privilege('warptalk_auth', 'workspace.workspaces', 'SELECT')
       OR has_schema_privilege('warptalk_auth', 'subscription', 'USAGE')
       OR has_table_privilege(
           'warptalk_auth',
           'subscription.subscriptions',
           'SELECT'
       ) THEN
        RAISE EXCEPTION 'Auth runtime can access another service schema';
    END IF;

    IF NOT has_table_privilege(
        'warptalk_translation_room',
        'translation_room.translation_rooms',
        'SELECT,INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'Translation Room runtime is missing owned-schema DML privileges';
    END IF;

    IF NOT has_table_privilege(
        'warptalk_transcript',
        'transcript.transcripts',
        'SELECT,INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'Transcript runtime is missing owned-schema DML privileges';
    END IF;

    IF NOT has_table_privilege(
        'warptalk_meeting',
        'meeting.meeting_rooms',
        'SELECT,INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'Meeting runtime is missing owned-schema DML privileges';
    END IF;

    IF NOT has_table_privilege(
        'warptalk_assistant',
        'assistant.assistant_conversations',
        'SELECT,INSERT,UPDATE,DELETE'
    ) THEN
        RAISE EXCEPTION 'Assistant runtime is missing owned-schema DML privileges';
    END IF;

    IF EXISTS (
        WITH ownership(role_name, owned_schemas) AS (
            VALUES
                ('warptalk_auth', ARRAY['auth', 'voice']),
                ('warptalk_workspace', ARRAY['workspace']),
                ('warptalk_translation_room', ARRAY['translation_room']),
                ('warptalk_transcript', ARRAY['transcript']),
                ('warptalk_notification', ARRAY['notification']),
                ('warptalk_meeting', ARRAY['meeting']),
                ('warptalk_assistant', ARRAY['assistant']),
                ('warptalk_billing', ARRAY['subscription'])
        ),
        service_schemas AS (
            SELECT oid, nspname
            FROM pg_namespace
            WHERE nspname IN (
                'auth', 'voice', 'workspace', 'translation_room', 'transcript',
                'notification', 'meeting', 'assistant', 'subscription'
            )
        )
        SELECT 1
        FROM ownership
        CROSS JOIN service_schemas
        WHERE NOT service_schemas.nspname = ANY(ownership.owned_schemas)
          AND (
              has_schema_privilege(
                  ownership.role_name,
                  service_schemas.oid,
                  'USAGE'
              )
              OR EXISTS (
                  SELECT 1
                  FROM pg_class service_object
                  WHERE service_object.relnamespace = service_schemas.oid
                    AND service_object.relkind IN ('r', 'p', 'v', 'm', 'f')
                    AND (
                        has_table_privilege(
                            ownership.role_name,
                            service_object.oid,
                            'SELECT'
                        )
                        OR has_table_privilege(
                            ownership.role_name,
                            service_object.oid,
                            'INSERT'
                        )
                        OR has_table_privilege(
                            ownership.role_name,
                            service_object.oid,
                            'UPDATE'
                        )
                        OR has_table_privilege(
                            ownership.role_name,
                            service_object.oid,
                            'DELETE'
                        )
                    )
              )
          )
    ) THEN
        RAISE EXCEPTION 'a runtime role has privileges outside its owned schemas';
    END IF;
END
$$;
SQL

echo "database boundary contract: PASS"
