-- Migration: Add can_create_meetings column to workspace.workspace_members
-- Created At: 2026-06-12

ALTER TABLE workspace.workspace_members
ADD COLUMN IF NOT EXISTS can_create_meetings BOOLEAN NOT NULL DEFAULT true;

-- Update existing external members to have can_create_meetings = false by default
UPDATE workspace.workspace_members
SET can_create_meetings = false
WHERE UPPER(membership_type) = 'EXTERNAL';
