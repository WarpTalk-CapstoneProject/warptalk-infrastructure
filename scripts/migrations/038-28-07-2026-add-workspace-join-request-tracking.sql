-- Migration: Add audit tracking for Workspace Join Requests.
-- Created At: 2026-07-28
--
-- Join Requests reuse workspace.workspace_invitations. Existing outbound
-- invitations remain compatible because all new columns are nullable.

ALTER TABLE workspace.workspace_invitations
  ADD COLUMN IF NOT EXISTS requested_by uuid,
  ADD COLUMN IF NOT EXISTS reviewed_by uuid,
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

-- requested_by / reviewed_by are AuthService user ids and deliberately carry NO
-- physical foreign key. This block previously added
-- workspace_invitations_requested_by_fkey and workspace_invitations_reviewed_by_fkey
-- pointing at auth.users, which are precisely the cross-service links
-- 043-30-07-2026-drop-cross-service-workspace-foreign-keys.sql removes ahead of the
-- logical-database split. Because this file's embedded date (28-07) sorts before
-- 043's (30-07) while having been authored later, any database that already ran 043
-- kept the constraints and then failed check-database-boundaries.sh, which aborts the
-- whole migrator chain. See 044-31-07-2026-drop-workspace-join-request-cross-service-fkeys.sql
-- for the cleanup applied to databases that already took the old version of this file.
COMMENT ON COLUMN workspace.workspace_invitations.requested_by IS 'External AuthService user id. No physical FK.';
COMMENT ON COLUMN workspace.workspace_invitations.reviewed_by IS 'External AuthService user id. No physical FK.';

UPDATE workspace.workspace_invitations
SET requested_by = invited_by
WHERE status = 'REQUESTED'
  AND requested_by IS NULL;

CREATE INDEX IF NOT EXISTS ix_workspace_invitations_workspace_id_status_created_at
  ON workspace.workspace_invitations (workspace_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_workspace_invitations_requested_by_status_created_at
  ON workspace.workspace_invitations (requested_by, status, created_at DESC)
  WHERE requested_by IS NOT NULL;
