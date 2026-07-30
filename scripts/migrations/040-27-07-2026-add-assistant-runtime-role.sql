DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_assistant_runtime') THEN
        CREATE ROLE warptalk_assistant_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA assistant TO warptalk_assistant_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA assistant
    TO warptalk_assistant_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA assistant
    TO warptalk_assistant_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA assistant
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_assistant_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA assistant
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_assistant_runtime;

COMMENT ON ROLE warptalk_assistant_runtime IS
    'Runtime DML access for the Assistant bounded context.';
