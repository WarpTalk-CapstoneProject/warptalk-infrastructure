-- Migration: Rename is_muted to is_translation_audio_enabled
-- Created At: 2026-05-15

ALTER TABLE translation_room.translation_room_participants 
RENAME COLUMN is_muted TO is_translation_audio_enabled;

-- The default value also needs to be updated from false to true because the boolean logic is inverted.
ALTER TABLE translation_room.translation_room_participants 
ALTER COLUMN is_translation_audio_enabled SET DEFAULT true;

-- Update existing records to invert the boolean logic (is_muted = false -> is_translation_audio_enabled = true)
UPDATE translation_room.translation_room_participants
SET is_translation_audio_enabled = NOT is_translation_audio_enabled;
