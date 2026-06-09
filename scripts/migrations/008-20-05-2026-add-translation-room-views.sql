-- Migration: 008-20-05-2026-add-translation-room-views.sql
-- Description: Create views in translation_room schema to access platform.supported_languages and auth.user_settings for Entity Framework Core scaffolding.

BEGIN;

CREATE OR REPLACE VIEW translation_room.supported_languages AS
SELECT code, name, native_name, is_active 
FROM platform.supported_languages;

CREATE OR REPLACE VIEW translation_room.user_settings AS
SELECT user_id, default_speak_language, default_listen_language 
FROM auth.user_settings;

COMMIT;
