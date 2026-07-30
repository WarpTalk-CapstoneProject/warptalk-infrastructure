-- Migration: Add is_ai_allowed column to workspace.workspace_documents table
-- Created At: 2026-07-22

ALTER TABLE workspace.workspace_documents 
ADD COLUMN IF NOT EXISTS is_ai_allowed BOOLEAN NOT NULL DEFAULT true;

-- Add conditional index for quick filtering of AI allowed documents
CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_is_ai_allowed 
ON workspace.workspace_documents (workspace_id, is_ai_allowed);
