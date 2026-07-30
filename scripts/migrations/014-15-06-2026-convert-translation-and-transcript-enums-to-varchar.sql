-- Convert translation_room enums to VARCHAR
ALTER TABLE translation_room.translation_rooms ALTER COLUMN status TYPE VARCHAR(255) USING status::VARCHAR;
ALTER TABLE translation_room.translation_rooms ALTER COLUMN status SET DEFAULT 'SCHEDULED';

ALTER TABLE translation_room.translation_room_participants ALTER COLUMN status TYPE VARCHAR(255) USING status::VARCHAR;
ALTER TABLE translation_room.translation_room_participants ALTER COLUMN status SET DEFAULT 'INVITED';

ALTER TABLE translation_room.translation_room_artifacts ALTER COLUMN artifact_type TYPE VARCHAR(255) USING artifact_type::VARCHAR;

-- Drop translation_room enum types
DROP TYPE IF EXISTS translation_room.room_status CASCADE;
DROP TYPE IF EXISTS translation_room.participant_status CASCADE;
DROP TYPE IF EXISTS translation_room.artifact_type CASCADE;


-- Convert transcript enums to VARCHAR
ALTER TABLE transcript.transcripts ALTER COLUMN status TYPE VARCHAR(255) USING status::VARCHAR;
ALTER TABLE transcript.transcripts ALTER COLUMN status SET DEFAULT 'RECORDING';

ALTER TABLE transcript.transcript_corrections ALTER COLUMN status TYPE VARCHAR(255) USING status::VARCHAR;
ALTER TABLE transcript.transcript_corrections ALTER COLUMN status SET DEFAULT 'PENDING';

ALTER TABLE transcript.transcript_corrections ALTER COLUMN correction_type TYPE VARCHAR(255) USING correction_type::VARCHAR;

-- Drop transcript enum types
DROP TYPE IF EXISTS transcript.transcript_status CASCADE;
DROP TYPE IF EXISTS transcript.correction_status CASCADE;
DROP TYPE IF EXISTS transcript.correction_type CASCADE;
