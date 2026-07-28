-- Notification runtime role. It owns delivery state and inbox deduplication,
-- but has no direct access to producer schemas.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'warptalk_notification_runtime'
    ) THEN
        CREATE ROLE warptalk_notification_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA notification TO warptalk_notification_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA notification
    TO warptalk_notification_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA notification
    TO warptalk_notification_runtime;

ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA notification
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_notification_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA notification
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_notification_runtime;

REVOKE ALL PRIVILEGES ON SCHEMA subscription
    FROM warptalk_notification_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA subscription
    FROM warptalk_notification_runtime;
REVOKE ALL PRIVILEGES ON SCHEMA workspace
    FROM warptalk_notification_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA workspace
    FROM warptalk_notification_runtime;

COMMENT ON ROLE warptalk_notification_runtime IS
    'Runtime DML access for Notification; producer data arrives through durable events.';
