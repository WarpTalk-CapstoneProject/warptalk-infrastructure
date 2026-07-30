CREATE TABLE meeting.meeting_chat_messages (
    id UUID PRIMARY KEY,
    meeting_room_id UUID NOT NULL REFERENCES meeting.meeting_rooms(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL,
    sender_user_id UUID,
    participant_id UUID REFERENCES meeting.meeting_participants(id) ON DELETE SET NULL,
    sender_display_name VARCHAR(255) NOT NULL,
    sender_type VARCHAR(50) NOT NULL DEFAULT 'user',
    message_type VARCHAR(50) NOT NULL DEFAULT 'text',
    original_language VARCHAR(50) NOT NULL,
    original_text TEXT NOT NULL,
    translation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    contains_warpbot_mention BOOLEAN NOT NULL DEFAULT FALSE,
    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE meeting.meeting_chat_translations (
    id UUID PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES meeting.meeting_chat_messages(id) ON DELETE CASCADE,
    meeting_room_id UUID NOT NULL,
    source_language VARCHAR(50) NOT NULL,
    target_language VARCHAR(50) NOT NULL,
    translated_text TEXT NOT NULL,
    model_used VARCHAR(100),
    confidence NUMERIC,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE meeting.meeting_chat_assistant_requests (
    id UUID PRIMARY KEY,
    trigger_message_id UUID NOT NULL REFERENCES meeting.meeting_chat_messages(id) ON DELETE CASCADE,
    meeting_room_id UUID NOT NULL,
    workspace_id UUID NOT NULL,
    requested_by_user_id UUID NOT NULL,
    prompt TEXT NOT NULL,
    context_scope VARCHAR(100) NOT NULL DEFAULT 'current_meeting',
    status VARCHAR(50) NOT NULL DEFAULT 'queued',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE meeting.meeting_chat_moderation_events (
    id UUID PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES meeting.meeting_chat_messages(id) ON DELETE CASCADE,
    meeting_room_id UUID NOT NULL,
    moderated_by_user_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
