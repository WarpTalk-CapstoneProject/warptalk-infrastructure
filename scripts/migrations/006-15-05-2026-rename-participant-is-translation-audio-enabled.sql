-- Migration: Rename is_muted to is_translation_audio_enabled
-- Created At: 2026-05-15

DO $$
BEGIN
    IF EXISTS (
<<<<<<< HEAD
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'translation_room' 
          AND table_name = 'translation_room_participants' 
          AND column_name = 'is_muted'
    ) THEN
        ALTER TABLE translation_room.translation_room_participants 
        RENAME COLUMN is_muted TO is_translation_audio_enabled;

        ALTER TABLE translation_room.translation_room_participants 
        ALTER COLUMN is_translation_audio_enabled SET DEFAULT true;

        UPDATE translation_room.translation_room_participants
        SET is_translation_audio_enabled = NOT is_translation_audio_enabled;
    END IF;
END $$;
=======
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'translation_room'
          AND table_name = 'translation_room_participants'
          AND column_name = 'is_muted'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'translation_room'
          AND table_name = 'translation_room_participants'
          AND column_name = 'is_translation_audio_enabled'
    ) THEN
        ALTER TABLE translation_room.translation_room_participants
            RENAME COLUMN is_muted TO is_translation_audio_enabled;

        -- The boolean meaning changed during the rename.
        UPDATE translation_room.translation_room_participants
        SET is_translation_audio_enabled = NOT is_translation_audio_enabled;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'translation_room'
          AND table_name = 'translation_room_participants'
          AND column_name = 'is_translation_audio_enabled'
    ) THEN
        ALTER TABLE translation_room.translation_room_participants
            ALTER COLUMN is_translation_audio_enabled SET DEFAULT true;
    END IF;
END
$$;
>>>>>>> origin/development
