-- Migration: 027-22-07-2026-add-voice-profile-language
-- Description:
--   voice.voice_profiles has no language column of its own — voice.voice_samples.language
--   exists, but a profile needs a display language before any sample is ever attached (the
--   AuthService voice-profile CRUD being added lets a user create a profile with just a
--   name + language, then optionally attach a reference sample afterwards). Add the column
--   directly on the profile so it always has one regardless of sample state.

BEGIN;

ALTER TABLE voice.voice_profiles
    ADD COLUMN IF NOT EXISTS language VARCHAR(15);

COMMIT;
