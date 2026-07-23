-- Migration: Host controls (lock, mute-on-entry) and LiveKit Egress recording support
-- Created At: 2026-07-23
-- WT-04: room lock + mute-on-entry host toggles.
-- WT-06: tracks the active LiveKit Egress recording, if any, for a meeting room.

ALTER TABLE meeting.meeting_rooms
ADD COLUMN IF NOT EXISTS is_locked BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS mute_on_entry BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS active_egress_id TEXT;
