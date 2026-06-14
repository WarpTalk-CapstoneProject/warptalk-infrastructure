CREATE TABLE IF NOT EXISTS meeting.meeting_invitations (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    meeting_room_id UUID NOT NULL REFERENCES meeting.meeting_rooms(id) ON DELETE CASCADE,
    invitee_user_id UUID,
    invitee_email VARCHAR(255),
    group_id UUID,
    workspace_id UUID NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING'::character varying,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_by UUID
);

CREATE INDEX IF NOT EXISTS idx_meeting_invitations_meeting_room_id ON meeting.meeting_invitations(meeting_room_id);
