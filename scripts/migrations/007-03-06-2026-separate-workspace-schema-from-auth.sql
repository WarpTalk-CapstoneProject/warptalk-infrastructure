-- Migration: Separate Workspace Schema from Auth Schema
-- Created At: 2026-06-03

-- 1. Create the workspace schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS workspace;

-- 2. Safely move or drop workspace tables from auth schema to workspace schema
DO $$
BEGIN
    -- Handle workspaces table
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'workspaces') THEN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'workspace' AND table_name = 'workspaces') THEN
            -- If it already exists in workspace schema, drop the duplicate old auth version
            DROP TABLE auth.workspaces CASCADE;
        ELSE
            -- Otherwise, move it to workspace schema
            ALTER TABLE auth.workspaces SET SCHEMA workspace;
        END IF;
    END IF;

    -- Handle workspace_members table
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'workspace_members') THEN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'workspace' AND table_name = 'workspace_members') THEN
            DROP TABLE auth.workspace_members CASCADE;
        ELSE
            ALTER TABLE auth.workspace_members SET SCHEMA workspace;
        END IF;
    END IF;

    -- Handle workspace_invitations table
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'workspace_invitations') THEN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'workspace' AND table_name = 'workspace_invitations') THEN
            DROP TABLE auth.workspace_invitations CASCADE;
        ELSE
            ALTER TABLE auth.workspace_invitations SET SCHEMA workspace;
        END IF;
    END IF;
END $$;

-- 3. Drop obsolete workspace_id column from user_roles
ALTER TABLE auth.user_roles DROP COLUMN IF EXISTS workspace_id;

-- 4. Create workspace_verified_domains table if it doesn't exist
CREATE TABLE IF NOT EXISTS workspace.workspace_verified_domains (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL REFERENCES workspace.workspaces(id) ON DELETE RESTRICT,
  domain VARCHAR(255) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  verification_method VARCHAR(50) NOT NULL,
  verification_token VARCHAR(255) NOT NULL,
  verified_at TIMESTAMPTZ,
  verified_by UUID,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID
);

-- 5. Create schema_migrations table for workspace if it doesn't exist
CREATE TABLE IF NOT EXISTS workspace.schema_migrations (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  migration_key VARCHAR(150) UNIQUE NOT NULL,
  migration_name VARCHAR(255) NOT NULL,
  checksum VARCHAR(128) NOT NULL,
  script_path VARCHAR(500),
  status VARCHAR(20) NOT NULL DEFAULT 'success',
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  execution_time_ms INT,
  error_message TEXT,
  applied_by VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);
