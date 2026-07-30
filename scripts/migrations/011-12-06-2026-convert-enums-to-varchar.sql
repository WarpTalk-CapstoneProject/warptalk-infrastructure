-- Remove custom PostgreSQL enum types and use VARCHAR

-- 1. Convert meeting.meeting_rooms.status to VARCHAR
ALTER TABLE meeting.meeting_rooms ALTER COLUMN status TYPE VARCHAR(255) USING status::VARCHAR;
ALTER TABLE meeting.meeting_rooms ALTER COLUMN status SET DEFAULT 'CREATED';

-- 2. Convert meeting.meeting_tracks.media_type to VARCHAR
ALTER TABLE meeting.meeting_tracks ALTER COLUMN media_type TYPE VARCHAR(255) USING media_type::VARCHAR;
ALTER TABLE meeting.meeting_tracks ALTER COLUMN media_type SET DEFAULT 'VIDEO';

-- 3. Drop the custom enum types if they are no longer used anywhere else
-- Check if other tables use them first? Actually we are fully migrating the schema.
DROP TYPE IF EXISTS meeting.meeting_status CASCADE;
DROP TYPE IF EXISTS meeting.media_type CASCADE;
