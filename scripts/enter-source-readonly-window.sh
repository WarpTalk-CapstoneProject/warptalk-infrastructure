#!/bin/sh
# Put the legacy shared-database service schemas into a rollback-safe,
# read-only window. This is intentionally guarded and must be run only after
# all application connections point at logical databases.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"

[ "${CONFIRM_SOURCE_READONLY:-}" = "YES" ] || {
  echo "Refusing source read-only transition: set CONFIRM_SOURCE_READONLY=YES" >&2
  exit 1
}

psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" <<'SQL'
BEGIN;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA auth, voice FROM warptalk_auth_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA workspace FROM warptalk_workspace_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA translation_room FROM warptalk_translation_room_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA transcript FROM warptalk_transcript_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA notification FROM warptalk_notification_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA meeting FROM warptalk_meeting_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA assistant FROM warptalk_assistant_runtime;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA subscription FROM warptalk_billing_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA auth, voice
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_auth_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA workspace
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_workspace_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA translation_room
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_translation_room_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA transcript
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_transcript_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA notification
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_notification_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA meeting
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_meeting_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA assistant
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_assistant_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA subscription
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM warptalk_billing_runtime;
COMMIT;
SQL
echo "Legacy shared-database schemas are read-only for service runtime roles."
