DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_transcript_runtime') THEN
        CREATE ROLE warptalk_transcript_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA transcript TO warptalk_transcript_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA transcript
    TO warptalk_transcript_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA transcript
    TO warptalk_transcript_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA transcript
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_transcript_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA transcript
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_transcript_runtime;

COMMENT ON ROLE warptalk_transcript_runtime IS
    'Runtime DML access for the Transcript bounded context.';
