-- Migration: Add meeting schema and tables
-- Created at: 2026-05-16

CREATE SCHEMA IF NOT EXISTS meeting;

CREATE TYPE meeting.meeting_status AS ENUM (
  'CREATED',
  'ACTIVE',
  'FINISHED'
);

CREATE TYPE meeting.media_type AS ENUM (
  'AUDIO',
  'VIDEO'
);

CREATE TABLE meeting.meeting_rooms (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  translation_room_id UUID NOT NULL,
  provider_room_name VARCHAR(255) NOT NULL,
  status meeting.meeting_status NOT NULL DEFAULT 'CREATED',
  
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID,
  
  ended_at TIMESTAMPTZ
);

CREATE TABLE meeting.meeting_participants (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  meeting_room_id UUID NOT NULL REFERENCES meeting.meeting_rooms(id) ON DELETE CASCADE,
  user_id UUID,
  provider_identity VARCHAR(255) NOT NULL,
  
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID,
  
  joined_at TIMESTAMPTZ,
  left_at TIMESTAMPTZ
);

CREATE TABLE meeting.meeting_tracks (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  meeting_participant_id UUID NOT NULL REFERENCES meeting.meeting_participants(id) ON DELETE CASCADE,
  provider_track_id VARCHAR(255) NOT NULL,
  media_type meeting.media_type NOT NULL,
  is_muted BOOLEAN NOT NULL DEFAULT false,
  
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID,
  
  published_at TIMESTAMPTZ,
  unpublished_at TIMESTAMPTZ
);

CREATE TABLE meeting.schema_migrations (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  migration_key VARCHAR(150) UNIQUE NOT NULL,
  migration_name VARCHAR(255) NOT NULL,
  checksum VARCHAR(128) NOT NULL,
  script_path VARCHAR(500),
  status VARCHAR(20) NOT NULL DEFAULT 'success',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  execution_time_ms INT,
  error_message TEXT,
  applied_by VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

-- Indexes for performance
CREATE INDEX idx_meeting_rooms_translation_room_id ON meeting.meeting_rooms(translation_room_id);
CREATE INDEX idx_meeting_participants_meeting_room_id ON meeting.meeting_participants(meeting_room_id);
CREATE INDEX idx_meeting_participants_user_id ON meeting.meeting_participants(user_id);
CREATE INDEX idx_meeting_tracks_meeting_participant_id ON meeting.meeting_tracks(meeting_participant_id);
