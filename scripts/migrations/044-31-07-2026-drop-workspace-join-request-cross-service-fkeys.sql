-- Migration: 044-31-07-2026-drop-workspace-join-request-cross-service-fkeys
-- Description:
--   Removes the workspace -> auth foreign keys that
--   038-28-07-2026-add-workspace-join-request-tracking.sql adds on
--   workspace.workspace_invitations.requested_by / .reviewed_by.
--
--   Those are exactly the cross-service links that
--   043-30-07-2026-drop-cross-service-workspace-foreign-keys.sql exists to remove
--   before each bounded context is extracted into its own logical database. 038 was
--   authored later but carries an earlier date (28-07 vs 30-07), and run-migrations.sh
--   orders by the embedded date, so on any database where 043 had already been applied
--   043 never ran again to clean up after it.
--
--   The result on production: check-database-boundaries.sh started failing with
--   "cross-schema foreign keys violate service database boundaries", which aborts the
--   migrator chain *before* run-logical-database-migrations.sh — blocking every
--   service-owned migration, not just workspace's.
--
--   Columns stay. requested_by / reviewed_by remain logical references to
--   AuthService user ids, validated through service contracts, exactly like the
--   columns 043 already stripped constraints from.

BEGIN;

ALTER TABLE IF EXISTS workspace.workspace_invitations
    DROP CONSTRAINT IF EXISTS workspace_invitations_requested_by_fkey,
    DROP CONSTRAINT IF EXISTS workspace_invitations_reviewed_by_fkey;

COMMIT;
