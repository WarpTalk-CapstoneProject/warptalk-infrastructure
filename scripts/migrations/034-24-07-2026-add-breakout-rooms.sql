-- Migration: Breakout rooms for meetings (scoped-down: host-created groups, each backed by
-- its own LiveKit provider room, with a manual or timed return to the main room).
-- Created At: 2026-07-24
--
-- NOTE: uses uuidv7()/schema "meeting" conventions to match migration 033
-- (add-polls-and-qa.sql) rather than the gen_random_uuid() sketched in the original ticket,
-- to stay consistent with every other meeting.* table.

CREATE TABLE IF NOT EXISTS meeting.breakout_sessions (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    parent_meeting_room_id UUID NOT NULL REFERENCES meeting.meeting_rooms(id) ON DELETE CASCADE,
    provider_room_name TEXT NOT NULL,
    label TEXT NOT NULL,
    duration_seconds INT,
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_breakout_sessions_parent_meeting_room_id ON meeting.breakout_sessions(parent_meeting_room_id);

CREATE TABLE IF NOT EXISTS meeting.breakout_assignments (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    breakout_session_id UUID NOT NULL REFERENCES meeting.breakout_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_breakout_assignments_session_id ON meeting.breakout_assignments(breakout_session_id);
CREATE INDEX IF NOT EXISTS idx_breakout_assignments_user_id ON meeting.breakout_assignments(user_id);
