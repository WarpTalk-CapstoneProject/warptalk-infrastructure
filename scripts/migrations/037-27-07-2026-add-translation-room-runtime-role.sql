DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warptalk_translation_room_runtime') THEN
        CREATE ROLE warptalk_translation_room_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA translation_room TO warptalk_translation_room_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA translation_room
    TO warptalk_translation_room_runtime;
GRANT USAGE, SELECT, UPDATE
    ON ALL SEQUENCES IN SCHEMA translation_room
    TO warptalk_translation_room_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA translation_room
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO warptalk_translation_room_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE warptalk_migrator IN SCHEMA translation_room
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES
    TO warptalk_translation_room_runtime;

COMMENT ON ROLE warptalk_translation_room_runtime IS
    'Runtime DML access for the Translation Room bounded context.';
