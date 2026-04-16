-- Migration: 001-14-04-2026-rename-meeting
-- Description: Rename "meeting" schema, tables, foreign keys, and service users to "translation_room"

DO $$
BEGIN
    -- 1. Rename schema
    IF EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = 'meeting') THEN
        ALTER SCHEMA meeting RENAME TO translation_room;
    END IF;

    -- 2. Rename tables in the new schema
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='translation_room' AND table_name='meetings') THEN
        ALTER TABLE translation_room.meetings RENAME TO translation_rooms;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='translation_room' AND table_name='meeting_participants') THEN
        ALTER TABLE translation_room.meeting_participants RENAME TO translation_room_participants;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='translation_room' AND table_name='meeting_audio_routes') THEN
        ALTER TABLE translation_room.meeting_audio_routes RENAME TO translation_room_audio_routes;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='translation_room' AND table_name='meeting_recordings') THEN
        ALTER TABLE translation_room.meeting_recordings RENAME TO translation_room_recordings;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='translation_room' AND table_name='meeting_summaries') THEN
        ALTER TABLE translation_room.meeting_summaries RENAME TO translation_room_summaries;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='translation_room' AND table_name='meeting_feedback') THEN
        ALTER TABLE translation_room.meeting_feedback RENAME TO translation_room_feedback;
    END IF;

    -- 3. Rename columns pointing to the old meetings table within the same schema
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_room_participants' AND column_name='meeting_id') THEN
        ALTER TABLE translation_room.translation_room_participants RENAME COLUMN meeting_id TO translation_room_id;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_room_audio_routes' AND column_name='meeting_id') THEN
        ALTER TABLE translation_room.translation_room_audio_routes RENAME COLUMN meeting_id TO translation_room_id;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_room_recordings' AND column_name='meeting_id') THEN
        ALTER TABLE translation_room.translation_room_recordings RENAME COLUMN meeting_id TO translation_room_id;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_room_summaries' AND column_name='meeting_id') THEN
        ALTER TABLE translation_room.translation_room_summaries RENAME COLUMN meeting_id TO translation_room_id;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='translation_room' AND table_name='translation_room_feedback' AND column_name='meeting_id') THEN
        ALTER TABLE translation_room.translation_room_feedback RENAME COLUMN meeting_id TO translation_room_id;
    END IF;

    -- 4. Rename columns in other schemas that reference the old meeting
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='transcript' AND table_name='transcripts' AND column_name='meeting_id') THEN
        ALTER TABLE transcript.transcripts RENAME COLUMN meeting_id TO translation_room_id;
    END IF;
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='subscription' AND table_name='usage_records' AND column_name='meeting_id') THEN
        ALTER TABLE subscription.usage_records RENAME COLUMN meeting_id TO translation_room_id;
    END IF;

    -- 5. Rename role
    IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'meeting_svc') THEN
        ALTER USER meeting_svc RENAME TO translation_room_svc;
    END IF;

END $$;
