-- Migration: Add content column to translation_room.translation_room_artifacts table
-- Created At: 2026-07-23
-- WT-13: AI meeting-summary artifacts store their structured JSON payload (overview,
-- decisions, action items) inline here instead of only behind file_url, since no real
-- blob storage is wired up for room artifacts yet.

ALTER TABLE translation_room.translation_room_artifacts
ADD COLUMN IF NOT EXISTS content TEXT;
