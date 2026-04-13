-- Migration: 001-14-04-2026-rename-meeting
-- Description: Rename "meeting" schema, tables, foreign keys, and service users to "translation_room"

-- 1. Rename schema
ALTER SCHEMA meeting RENAME TO translation_room;

-- 2. Rename tables in the new schema
ALTER TABLE translation_room.meetings RENAME TO translation_rooms;
ALTER TABLE translation_room.meeting_participants RENAME TO translation_room_participants;
ALTER TABLE translation_room.meeting_audio_routes RENAME TO translation_room_audio_routes;
ALTER TABLE translation_room.meeting_recordings RENAME TO translation_room_recordings;
ALTER TABLE translation_room.meeting_summaries RENAME TO translation_room_summaries;
ALTER TABLE translation_room.meeting_feedback RENAME TO translation_room_feedback;

-- 3. Rename columns pointing to the old meetings table within the same schema
ALTER TABLE translation_room.translation_room_participants RENAME COLUMN meeting_id TO translation_room_id;
ALTER TABLE translation_room.translation_room_audio_routes RENAME COLUMN meeting_id TO translation_room_id;
ALTER TABLE translation_room.translation_room_recordings RENAME COLUMN meeting_id TO translation_room_id;
ALTER TABLE translation_room.translation_room_summaries RENAME COLUMN meeting_id TO translation_room_id;
ALTER TABLE translation_room.translation_room_feedback RENAME COLUMN meeting_id TO translation_room_id;

-- 4. Rename columns in other schemas that reference the old meeting
ALTER TABLE transcript.transcripts RENAME COLUMN meeting_id TO translation_room_id;
ALTER TABLE subscription.usage_records RENAME COLUMN meeting_id TO translation_room_id;

-- 5. Rename role
ALTER USER meeting_svc RENAME TO translation_room_svc;

-- Note: Indexes, constraints, and sequences technically keep their original names unless explicitly renamed.
-- PostgreSQL doesn't require index renaming for functionality, but for completeness, we could alter them as well.
