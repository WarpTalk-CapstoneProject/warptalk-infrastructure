#!/bin/sh
# Provision LOGIN roles from deployment secrets after schema migrations.
# Passwords stay in environment variables and are never committed to SQL files.
set -eu

: "${SUBSCRIPTION_DB_PASSWORD:?SUBSCRIPTION_DB_PASSWORD is required}"
: "${WORKSPACE_DB_PASSWORD:?WORKSPACE_DB_PASSWORD is required}"
: "${NOTIFICATION_DB_PASSWORD:?NOTIFICATION_DB_PASSWORD is required}"
: "${AUTH_DB_PASSWORD:?AUTH_DB_PASSWORD is required}"
: "${TRANSLATION_ROOM_DB_PASSWORD:?TRANSLATION_ROOM_DB_PASSWORD is required}"
: "${TRANSCRIPT_DB_PASSWORD:?TRANSCRIPT_DB_PASSWORD is required}"
: "${MEETING_DB_PASSWORD:?MEETING_DB_PASSWORD is required}"
: "${ASSISTANT_DB_PASSWORD:?ASSISTANT_DB_PASSWORD is required}"
: "${MONITOR_DB_PASSWORD:?MONITOR_DB_PASSWORD is required}"

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-warptalk}"
export PGPASSWORD="${PGPASSWORD:-}"

psql \
  -X \
  -v ON_ERROR_STOP=1 \
  -v "subscription_db_password=$SUBSCRIPTION_DB_PASSWORD" \
  -v "workspace_db_password=$WORKSPACE_DB_PASSWORD" \
  -v "notification_db_password=$NOTIFICATION_DB_PASSWORD" \
  -v "auth_db_password=$AUTH_DB_PASSWORD" \
  -v "translation_room_db_password=$TRANSLATION_ROOM_DB_PASSWORD" \
  -v "transcript_db_password=$TRANSCRIPT_DB_PASSWORD" \
  -v "meeting_db_password=$MEETING_DB_PASSWORD" \
  -v "assistant_db_password=$ASSISTANT_DB_PASSWORD" \
  -v "monitor_db_password=$MONITOR_DB_PASSWORD" \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" <<'SQL'
SELECT 'CREATE ROLE warptalk_billing LOGIN INHERIT'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_billing'
)
\gexec

ALTER ROLE warptalk_billing
    LOGIN
    INHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD :'subscription_db_password';

GRANT warptalk_billing_runtime TO warptalk_billing;

SELECT 'CREATE ROLE warptalk_workspace LOGIN INHERIT'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_workspace'
)
\gexec

ALTER ROLE warptalk_workspace
    LOGIN
    INHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD :'workspace_db_password';

GRANT warptalk_workspace_runtime TO warptalk_workspace;

SELECT 'CREATE ROLE warptalk_notification LOGIN INHERIT'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_notification'
)
\gexec

ALTER ROLE warptalk_notification
    LOGIN
    INHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD :'notification_db_password';

GRANT warptalk_notification_runtime TO warptalk_notification;

SELECT 'CREATE ROLE warptalk_auth LOGIN INHERIT'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_auth'
)
\gexec

ALTER ROLE warptalk_auth
    LOGIN
    INHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD :'auth_db_password';

GRANT warptalk_auth_runtime TO warptalk_auth;

SELECT 'CREATE ROLE warptalk_translation_room LOGIN INHERIT'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_translation_room')
\gexec
ALTER ROLE warptalk_translation_room
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
    PASSWORD :'translation_room_db_password';
GRANT warptalk_translation_room_runtime TO warptalk_translation_room;

SELECT 'CREATE ROLE warptalk_transcript LOGIN INHERIT'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_transcript')
\gexec
ALTER ROLE warptalk_transcript
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
    PASSWORD :'transcript_db_password';
GRANT warptalk_transcript_runtime TO warptalk_transcript;

SELECT 'CREATE ROLE warptalk_meeting LOGIN INHERIT'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_meeting')
\gexec
ALTER ROLE warptalk_meeting
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
    PASSWORD :'meeting_db_password';
GRANT warptalk_meeting_runtime TO warptalk_meeting;

SELECT 'CREATE ROLE warptalk_assistant LOGIN INHERIT'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_assistant')
\gexec
ALTER ROLE warptalk_assistant
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
    PASSWORD :'assistant_db_password';
GRANT warptalk_assistant_runtime TO warptalk_assistant;

SELECT 'CREATE ROLE warptalk_monitor LOGIN INHERIT'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_monitor')
\gexec
ALTER ROLE warptalk_monitor
    LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
    PASSWORD :'monitor_db_password';
GRANT pg_monitor TO warptalk_monitor;
SQL

echo "Service database users provisioned."
