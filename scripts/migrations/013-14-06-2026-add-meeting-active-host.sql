ALTER TABLE meeting.meeting_rooms 
ADD COLUMN IF NOT EXISTS active_host_id UUID;
