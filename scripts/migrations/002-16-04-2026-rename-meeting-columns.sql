-- Migration: 002-16-04-2026-rename-meeting-columns
-- Description: Rename meeting_type and meeting_code inside translation_rooms

DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_rooms' AND column_name='meeting_type') THEN
        ALTER TABLE translation_room.translation_rooms RENAME COLUMN meeting_type TO translation_room_type;
    END IF;

    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_rooms' AND column_name='meeting_code') THEN
        ALTER TABLE translation_room.translation_rooms RENAME COLUMN meeting_code TO translation_room_code;
    END IF;
END $$;
