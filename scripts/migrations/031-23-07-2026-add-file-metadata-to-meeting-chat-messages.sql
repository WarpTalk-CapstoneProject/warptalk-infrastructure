-- Migration: Add file metadata columns to meeting.meeting_chat_messages
-- Created At: 2026-07-23
-- WT-10: in-meeting file sharing. New messageType "file" reuses the existing chat
-- message row; these columns are only populated for that type.

ALTER TABLE meeting.meeting_chat_messages
ADD COLUMN IF NOT EXISTS file_url TEXT,
ADD COLUMN IF NOT EXISTS file_name VARCHAR(255),
ADD COLUMN IF NOT EXISTS file_size_bytes BIGINT,
ADD COLUMN IF NOT EXISTS content_type VARCHAR(255);
