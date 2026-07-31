-- Remove physical Workspace -> Auth foreign keys before each bounded context
-- is extracted into its own logical database. The UUID columns remain logical
-- references validated through service contracts and event-driven workflows.

BEGIN;

ALTER TABLE IF EXISTS workspace.workspace_invitations
    DROP CONSTRAINT IF EXISTS workspace_invitations_invited_by_fkey,
    DROP CONSTRAINT IF EXISTS workspace_invitations_role_id_fkey;

ALTER TABLE IF EXISTS workspace.workspace_members
    DROP CONSTRAINT IF EXISTS workspace_members_removed_by_fkey,
    DROP CONSTRAINT IF EXISTS workspace_members_role_id_fkey,
    DROP CONSTRAINT IF EXISTS workspace_members_user_id_fkey;

ALTER TABLE IF EXISTS workspace.workspace_verified_domains
    DROP CONSTRAINT IF EXISTS workspace_verified_domains_created_by_fkey,
    DROP CONSTRAINT IF EXISTS workspace_verified_domains_updated_by_fkey,
    DROP CONSTRAINT IF EXISTS workspace_verified_domains_verified_by_fkey;

ALTER TABLE IF EXISTS workspace.workspaces
    DROP CONSTRAINT IF EXISTS workspaces_created_by_fkey,
    DROP CONSTRAINT IF EXISTS workspaces_deleted_by_fkey,
    DROP CONSTRAINT IF EXISTS workspaces_owner_id_fkey,
    DROP CONSTRAINT IF EXISTS workspaces_updated_by_fkey;

COMMIT;
