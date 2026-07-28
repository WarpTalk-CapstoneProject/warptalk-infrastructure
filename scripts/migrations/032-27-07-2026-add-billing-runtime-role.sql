-- Keep object ownership stable even if the deployment login changes.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'warptalk_migrator'
    ) THEN
        CREATE ROLE warptalk_migrator
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'warptalk_billing_runtime'
    ) THEN
        CREATE ROLE warptalk_billing_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE, CREATE
    ON SCHEMA auth, voice, workspace, translation_room, transcript,
        notification, meeting, assistant, subscription
    TO warptalk_migrator;

GRANT USAGE ON SCHEMA subscription TO warptalk_billing_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA subscription
    TO warptalk_billing_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA subscription
    TO warptalk_billing_runtime;

-- New tables and sequences are created under the stable migration owner.
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA subscription
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_billing_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA subscription
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_billing_runtime;

-- Explicit boundary documentation and defence in depth. PostgreSQL does not
-- grant these privileges by default, but keeping the revoke here makes the
-- intended isolation testable and resilient to earlier manual grants.
REVOKE ALL PRIVILEGES ON SCHEMA workspace FROM warptalk_billing_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA workspace
    FROM warptalk_billing_runtime;

COMMENT ON ROLE warptalk_billing_runtime IS
    'Runtime DML access for Billing; workspace data must be obtained through Workspace gRPC.';
