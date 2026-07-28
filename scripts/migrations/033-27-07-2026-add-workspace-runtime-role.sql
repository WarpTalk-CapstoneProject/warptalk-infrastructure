-- Workspace runtime role. Object ownership and DDL remain with the deployment
-- administrator so runtime compromise cannot alter the schema.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'warptalk_workspace_runtime'
    ) THEN
        CREATE ROLE warptalk_workspace_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA workspace TO warptalk_workspace_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA workspace
    TO warptalk_workspace_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA workspace
    TO warptalk_workspace_runtime;

ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA workspace
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_workspace_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA workspace
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_workspace_runtime;

REVOKE ALL PRIVILEGES ON SCHEMA auth FROM warptalk_workspace_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth
    FROM warptalk_workspace_runtime;
REVOKE ALL PRIVILEGES ON SCHEMA subscription FROM warptalk_workspace_runtime;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA subscription
    FROM warptalk_workspace_runtime;

COMMENT ON ROLE warptalk_workspace_runtime IS
    'Runtime DML access for Workspace; other bounded contexts are accessed through service contracts.';
