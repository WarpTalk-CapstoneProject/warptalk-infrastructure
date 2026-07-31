-- Migration: Add audit tracking for Workspace Join Requests.
-- Created At: 2026-07-28
--
-- Join Requests reuse workspace.workspace_invitations. Existing outbound
-- invitations remain compatible because all new columns are nullable.

ALTER TABLE workspace.workspace_invitations
  ADD COLUMN IF NOT EXISTS requested_by uuid,
  ADD COLUMN IF NOT EXISTS reviewed_by uuid,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workspace_invitations_requested_by_fkey'
  ) THEN
    ALTER TABLE workspace.workspace_invitations
      ADD CONSTRAINT workspace_invitations_requested_by_fkey
      FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workspace_invitations_reviewed_by_fkey'
  ) THEN
    ALTER TABLE workspace.workspace_invitations
      ADD CONSTRAINT workspace_invitations_reviewed_by_fkey
      FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

UPDATE workspace.workspace_invitations
SET requested_by = invited_by
WHERE status = 'REQUESTED'
  AND requested_by IS NULL;

CREATE INDEX IF NOT EXISTS ix_workspace_invitations_workspace_id_status_created_at
  ON workspace.workspace_invitations (workspace_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_workspace_invitations_requested_by_status_created_at
  ON workspace.workspace_invitations (requested_by, status, created_at DESC)
  WHERE requested_by IS NOT NULL;
