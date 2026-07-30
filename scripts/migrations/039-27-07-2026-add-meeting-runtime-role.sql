DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_meeting_runtime') THEN
        CREATE ROLE warptalk_meeting_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA meeting TO warptalk_meeting_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA meeting
    TO warptalk_meeting_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA meeting
    TO warptalk_meeting_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA meeting
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_meeting_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA meeting
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_meeting_runtime;

COMMENT ON ROLE warptalk_meeting_runtime IS
    'Runtime DML access for the Meeting bounded context.';
