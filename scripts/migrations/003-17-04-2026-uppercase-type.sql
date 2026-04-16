-- Migration: 003-17-04-2026-uppercase-type
-- Description: Convert translation_room_type values and defaults to UPPERCASE

DO $$
BEGIN
    -- Update any existing data to uppercase
    UPDATE translation_room.translation_rooms
    SET translation_room_type = UPPER(translation_room_type);

    -- Change the default string constraint from 'group' to 'GROUP'
    ALTER TABLE translation_room.translation_rooms
    ALTER COLUMN translation_room_type SET DEFAULT 'GROUP';
END $$;
