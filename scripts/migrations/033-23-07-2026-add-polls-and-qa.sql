-- Migration: Polls + Q&A for meetings
-- Created At: 2026-07-23

CREATE TABLE IF NOT EXISTS meeting.polls (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    meeting_room_id UUID NOT NULL REFERENCES meeting.meeting_rooms(id) ON DELETE CASCADE,
    created_by UUID NOT NULL,
    question TEXT NOT NULL,
    is_multiple_choice BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    closed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_polls_meeting_room_id ON meeting.polls(meeting_room_id);

CREATE TABLE IF NOT EXISTS meeting.poll_options (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    poll_id UUID NOT NULL REFERENCES meeting.polls(id) ON DELETE CASCADE,
    label TEXT NOT NULL,
    position INT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_poll_options_poll_id ON meeting.poll_options(poll_id);

CREATE TABLE IF NOT EXISTS meeting.poll_votes (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    poll_id UUID NOT NULL REFERENCES meeting.polls(id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES meeting.poll_options(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    UNIQUE (poll_id, option_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_id ON meeting.poll_votes(poll_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_id_user_id ON meeting.poll_votes(poll_id, user_id);

CREATE TABLE IF NOT EXISTS meeting.questions (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    meeting_room_id UUID NOT NULL REFERENCES meeting.meeting_rooms(id) ON DELETE CASCADE,
    asked_by UUID NOT NULL,
    asked_by_display_name TEXT NOT NULL,
    body TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    answered_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_questions_meeting_room_id ON meeting.questions(meeting_room_id);

CREATE TABLE IF NOT EXISTS meeting.question_votes (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    question_id UUID NOT NULL REFERENCES meeting.questions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    UNIQUE (question_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_question_votes_question_id ON meeting.question_votes(question_id);
