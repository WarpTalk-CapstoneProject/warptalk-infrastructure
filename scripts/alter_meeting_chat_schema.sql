SET search_path TO meeting, public;

-- Add missing audit columns to meeting_rooms and meeting_participants
ALTER TABLE IF EXISTS meeting_rooms 
    ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true, 
    ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now(), 
    ADD COLUMN IF NOT EXISTS created_by uuid, 
    ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now(), 
    ADD COLUMN IF NOT EXISTS updated_by uuid, 
    ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone, 
    ADD COLUMN IF NOT EXISTS deleted_by uuid, 
    ADD COLUMN IF NOT EXISTS ended_at timestamp with time zone;

ALTER TABLE IF EXISTS meeting_participants 
    ADD COLUMN IF NOT EXISTS created_at timestamp with time zone DEFAULT now(), 
    ADD COLUMN IF NOT EXISTS created_by uuid, 
    ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now(), 
    ADD COLUMN IF NOT EXISTS updated_by uuid, 
    ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone, 
    ADD COLUMN IF NOT EXISTS deleted_by uuid, 
    ADD COLUMN IF NOT EXISTS joined_at timestamp with time zone, 
    ADD COLUMN IF NOT EXISTS left_at timestamp with time zone;

CREATE TABLE IF NOT EXISTS meeting_chat_messages (
    id uuid NOT NULL,
    meeting_room_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    sender_user_id uuid,
    participant_id uuid,
    sender_display_name character varying(255) NOT NULL,
    sender_type character varying(50) DEFAULT 'user'::character varying NOT NULL,
    message_type character varying(50) DEFAULT 'text'::character varying NOT NULL,
    original_language character varying(50) NOT NULL,
    original_text text NOT NULL,
    translation_enabled boolean NOT NULL,
    is_hidden boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    mentions jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT meeting_chat_messages_pkey PRIMARY KEY (id),
    CONSTRAINT meeting_chat_messages_meeting_room_id_fkey FOREIGN KEY (meeting_room_id) REFERENCES meeting_rooms (id) ON DELETE CASCADE,
    CONSTRAINT meeting_chat_messages_participant_id_fkey FOREIGN KEY (participant_id) REFERENCES meeting_participants (id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS meeting_chat_translations (
    id uuid NOT NULL,
    message_id uuid NOT NULL,
    meeting_room_id uuid NOT NULL,
    source_language character varying(50) NOT NULL,
    target_language character varying(50) NOT NULL,
    translated_text text NOT NULL,
    model_used character varying(100),
    confidence double precision,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meeting_chat_translations_pkey PRIMARY KEY (id),
    CONSTRAINT meeting_chat_translations_message_id_fkey FOREIGN KEY (message_id) REFERENCES meeting_chat_messages (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS meeting_chat_assistant_requests (
    id uuid NOT NULL,
    meeting_room_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    trigger_message_id uuid,
    prompt text NOT NULL,
    context_scope character varying(100) DEFAULT 'current_meeting'::character varying NOT NULL,
    status character varying(50) DEFAULT 'queued'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT meeting_chat_assistant_requests_pkey PRIMARY KEY (id),
    CONSTRAINT meeting_chat_assistant_requests_trigger_message_id_fkey FOREIGN KEY (trigger_message_id) REFERENCES meeting_chat_messages (id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS meeting_chat_moderation_events (
    id uuid NOT NULL,
    message_id uuid NOT NULL,
    meeting_room_id uuid NOT NULL,
    moderated_by_user_id uuid,
    action character varying(50) NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT meeting_chat_moderation_events_pkey PRIMARY KEY (id),
    CONSTRAINT meeting_chat_moderation_events_message_id_fkey FOREIGN KEY (message_id) REFERENCES meeting_chat_messages (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS meeting_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    meeting_room_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    invitee_user_id uuid,
    invitee_email character varying(255),
    group_id uuid,
    status character varying(50) DEFAULT 'PENDING'::character varying NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT meeting_invitations_pkey PRIMARY KEY (id),
    CONSTRAINT meeting_invitations_meeting_room_id_fkey FOREIGN KEY (meeting_room_id) REFERENCES meeting_rooms (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_meeting_invitations_meeting_room_id ON meeting_invitations (meeting_room_id);

CREATE TABLE IF NOT EXISTS meeting_tracks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    meeting_participant_id uuid NOT NULL,
    provider_track_id character varying(255) NOT NULL,
    media_type character varying(255) DEFAULT 'VIDEO'::character varying NOT NULL,
    is_muted boolean NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    published_at timestamp with time zone,
    unpublished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    CONSTRAINT meeting_tracks_pkey PRIMARY KEY (id),
    CONSTRAINT meeting_tracks_meeting_participant_id_fkey FOREIGN KEY (meeting_participant_id) REFERENCES meeting_participants (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_meeting_tracks_meeting_participant_id ON meeting_tracks (meeting_participant_id);
