-- Auth owns identity data and the closely related voice-profile aggregate.
-- Both schemas move together when Auth receives its own logical database.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'warptalk_auth_runtime'
    ) THEN
        CREATE ROLE warptalk_auth_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA auth, voice TO warptalk_auth_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA auth, voice
    TO warptalk_auth_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA auth, voice
    TO warptalk_auth_runtime;

ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA auth
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_auth_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA auth
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_auth_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA voice
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_auth_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA voice
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_auth_runtime;

REVOKE ALL PRIVILEGES ON SCHEMA workspace
    FROM warptalk_auth_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA workspace
    FROM warptalk_auth_runtime;
REVOKE ALL PRIVILEGES ON SCHEMA subscription
    FROM warptalk_auth_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA subscription
    FROM warptalk_auth_runtime;

COMMENT ON ROLE warptalk_auth_runtime IS
    'Runtime DML access for Auth-owned identity and voice-profile schemas.';
