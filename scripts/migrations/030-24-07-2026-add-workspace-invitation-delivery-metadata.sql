-- Migration 030: Add Resend delivery metadata fields to workspace_invitations table
-- Author: WarpTalk Team
-- Date: 2026-07-24

ALTER TABLE workspace.workspace_invitations
ADD COLUMN IF NOT EXISTS delivery_status VARCHAR(50) DEFAULT 'NotSent' NOT NULL,
ADD COLUMN IF NOT EXISTS provider_message_id VARCHAR(255) NULL,
ADD COLUMN IF NOT EXISTS last_sent_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS sent_count INT DEFAULT 0 NOT NULL;

-- Make token_hash nullable for email-bound invitations
ALTER TABLE workspace.workspace_invitations
ALTER COLUMN token_hash DROP NOT NULL;
