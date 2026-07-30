-- Add dynamic mentions to meeting_chat_messages table

ALTER TABLE meeting.meeting_chat_messages
ADD COLUMN mentions JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE meeting.meeting_chat_messages
DROP COLUMN contains_warpbot_mention;
