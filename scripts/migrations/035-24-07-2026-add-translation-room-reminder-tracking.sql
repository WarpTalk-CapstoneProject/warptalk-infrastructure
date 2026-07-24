-- Migration: Track sent scheduled-meeting reminders per window
-- Created At: 2026-07-24
-- WT-14: reminder background worker checks these columns so a room scheduled within the
-- T-10min / T-1min windows is only ever reminded once per window, even across worker restarts.

ALTER TABLE translation_room.translation_rooms
ADD COLUMN IF NOT EXISTS reminder_10min_sent_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS reminder_1min_sent_at TIMESTAMPTZ NULL;
