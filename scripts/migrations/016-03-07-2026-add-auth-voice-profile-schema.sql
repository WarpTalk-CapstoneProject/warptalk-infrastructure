-- Migration: Add voice profile metadata tables for AuthService-managed voice profiles
-- Scope: metadata, consent, and third-party storage file references. Raw audio is not stored in AuthService DB.

CREATE SCHEMA IF NOT EXISTS voice;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'consent_status') THEN
        CREATE TYPE consent_status AS ENUM ('granted', 'revoked', 'expired');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS voice.voice_profiles (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  workspace_id UUID,
  display_name VARCHAR(100),
  provider VARCHAR(50),
  embedding_ref VARCHAR(500),
  status VARCHAR(20) NOT NULL DEFAULT 'pending_consent',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE IF NOT EXISTS voice.voice_consents (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  voice_profile_id UUID,
  consent_type VARCHAR(50) NOT NULL,
  consent_status consent_status NOT NULL,
  consent_text_version VARCHAR(50) NOT NULL,
  granted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE IF NOT EXISTS voice.voice_samples (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  voice_profile_id UUID NOT NULL,
  sample_type VARCHAR(30) NOT NULL,
  file_url VARCHAR(500),
  duration_seconds INT,
  language VARCHAR(15),
  contains_raw_audio BOOLEAN NOT NULL DEFAULT true,
  retention_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE INDEX IF NOT EXISTS idx_voice_profiles_user_id_status ON voice.voice_profiles (user_id, status);
CREATE INDEX IF NOT EXISTS idx_voice_profiles_workspace_id ON voice.voice_profiles (workspace_id);
CREATE INDEX IF NOT EXISTS idx_voice_samples_profile_id ON voice.voice_samples (voice_profile_id);
CREATE INDEX IF NOT EXISTS idx_voice_consents_profile_type ON voice.voice_consents (voice_profile_id, consent_type, created_at);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'voice_consents_voice_profile_id_fkey'
    ) THEN
        ALTER TABLE voice.voice_consents
        ADD CONSTRAINT voice_consents_voice_profile_id_fkey
        FOREIGN KEY (voice_profile_id)
        REFERENCES voice.voice_profiles (id)
        DEFERRABLE INITIALLY IMMEDIATE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'voice_samples_voice_profile_id_fkey'
    ) THEN
        ALTER TABLE voice.voice_samples
        ADD CONSTRAINT voice_samples_voice_profile_id_fkey
        FOREIGN KEY (voice_profile_id)
        REFERENCES voice.voice_profiles (id)
        DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

COMMENT ON COLUMN voice.voice_profiles.embedding_ref IS 'Reference to voice embedding/model storage, not raw audio.';
COMMENT ON COLUMN voice.voice_samples.file_url IS 'Third-party storage URL for the uploaded audio file.';
