-- Migration: 006-14-05-2026-convert-transcript-status-to-enum
-- Description: Convert VARCHAR status columns in transcript schema to PostgreSQL ENUM types

-- 1. Create ENUM types
CREATE TYPE transcript.transcript_status AS ENUM ('RECORDING', 'FINALIZING', 'FINALIZED', 'ARCHIVED');
CREATE TYPE transcript.correction_status AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');
CREATE TYPE transcript.correction_type AS ENUM ('STT', 'TRANSLATION');

-- 2. Convert transcript status
ALTER TABLE transcript.transcripts ALTER COLUMN status DROP DEFAULT;
ALTER TABLE transcript.transcripts 
  ALTER COLUMN status TYPE transcript.transcript_status 
  USING UPPER(status)::transcript.transcript_status;
ALTER TABLE transcript.transcripts ALTER COLUMN status SET DEFAULT 'RECORDING'::transcript.transcript_status;

-- 3. Convert transcript_corrections status and correction_type
ALTER TABLE transcript.transcript_corrections ALTER COLUMN status DROP DEFAULT;
ALTER TABLE transcript.transcript_corrections 
  ALTER COLUMN status TYPE transcript.correction_status 
  USING UPPER(status)::transcript.correction_status;
ALTER TABLE transcript.transcript_corrections ALTER COLUMN status SET DEFAULT 'ACCEPTED'::transcript.correction_status;

ALTER TABLE transcript.transcript_corrections ALTER COLUMN correction_type DROP DEFAULT;
ALTER TABLE transcript.transcript_corrections 
  ALTER COLUMN correction_type TYPE transcript.correction_type 
  USING UPPER(correction_type)::transcript.correction_type;
