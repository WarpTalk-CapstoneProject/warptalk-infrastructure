-- Migration: Add Workspace Documents, Access Policies, Audits and Glossaries
-- Created At: 2026-06-03

-- 1. Alter workspace_verified_domains unique constraint to conditional unique index
ALTER TABLE workspace.workspace_verified_domains DROP CONSTRAINT IF EXISTS workspace_verified_domains_domain_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_workspace_verified_domains_unique_verified 
ON workspace.workspace_verified_domains (domain) 
WHERE status = 'verified';

-- 2. Create Workspace Documents Table
CREATE TABLE IF NOT EXISTS workspace.workspace_documents (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL REFERENCES workspace.workspaces(id) ON DELETE RESTRICT,
  uploaded_by UUID,
  owner_id UUID,
  name VARCHAR(255) NOT NULL,
  file_name VARCHAR(255) NOT NULL,
  file_extension VARCHAR(20) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  size_bytes BIGINT NOT NULL,
  storage_provider VARCHAR(50) NOT NULL,
  storage_key VARCHAR(500) NOT NULL,
  source_type VARCHAR(50) NOT NULL,
  document_type VARCHAR(50) NOT NULL,
  source_language VARCHAR(20),
  detected_language VARCHAR(20),
  business_domain VARCHAR(100),
  summary TEXT,
  keywords JSONB,
  ai_eligible BOOLEAN NOT NULL DEFAULT true,
  ai_usage_policy JSONB,
  ingestion_status VARCHAR(30) NOT NULL DEFAULT 'pending',
  last_indexed_at TIMESTAMPTZ,
  index_version VARCHAR(50),
  is_sensitive BOOLEAN NOT NULL DEFAULT false,
  confidentiality_level VARCHAR(30) NOT NULL DEFAULT 'public_internal',
  retention_state VARCHAR(30) NOT NULL DEFAULT 'active',
  status VARCHAR(30) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_id ON workspace.workspace_documents (workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_status ON workspace.workspace_documents (workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_retention ON workspace.workspace_documents (workspace_id, retention_state);
CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_ai ON workspace.workspace_documents (workspace_id, ai_eligible);
CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_confidentiality ON workspace.workspace_documents (workspace_id, confidentiality_level);
CREATE INDEX IF NOT EXISTS idx_workspace_documents_workspace_lang ON workspace.workspace_documents (workspace_id, source_language);

-- 3. Create Workspace Document Access Policies Table
CREATE TABLE IF NOT EXISTS workspace.workspace_document_access_policies (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  document_id UUID NOT NULL REFERENCES workspace.workspace_documents(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspace.workspaces(id) ON DELETE RESTRICT,
  subject_type VARCHAR(30) NOT NULL,
  subject_id UUID,
  role_key VARCHAR(30),
  permission VARCHAR(30) NOT NULL,
  effect VARCHAR(20) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID
);

CREATE INDEX IF NOT EXISTS idx_doc_access_policies_doc_id ON workspace.workspace_document_access_policies (document_id);
CREATE INDEX IF NOT EXISTS idx_doc_access_policies_lookup ON workspace.workspace_document_access_policies (document_id, subject_type, subject_id);

-- 4. Create Workspace Document Audits Table
CREATE TABLE IF NOT EXISTS workspace.workspace_document_audits (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  document_id UUID NOT NULL REFERENCES workspace.workspace_documents(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspace.workspaces(id) ON DELETE RESTRICT,
  actor_id UUID,
  action VARCHAR(50) NOT NULL,
  action_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  metadata JSONB,
  ip_address VARCHAR(64),
  user_agent VARCHAR(500)
);

CREATE INDEX IF NOT EXISTS idx_workspace_doc_audits_doc_id ON workspace.workspace_document_audits (document_id);
CREATE INDEX IF NOT EXISTS idx_workspace_doc_audits_workspace_action ON workspace.workspace_document_audits (workspace_id, action_at);
CREATE INDEX IF NOT EXISTS idx_workspace_doc_audits_actor_action ON workspace.workspace_document_audits (actor_id, action_at);

-- 5. Create Workspace Knowledge Glossaries Table
CREATE TABLE IF NOT EXISTS workspace.workspace_knowledge_glossaries (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL REFERENCES workspace.workspaces(id) ON DELETE RESTRICT,
  name VARCHAR(255) NOT NULL,
  business_domain VARCHAR(100),
  source_language VARCHAR(20) NOT NULL,
  target_language VARCHAR(20) NOT NULL,
  term VARCHAR(255) NOT NULL,
  preferred_translation VARCHAR(255) NOT NULL,
  part_of_speech VARCHAR(50),
  definition TEXT,
  usage_note TEXT,
  status VARCHAR(30) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  UNIQUE (workspace_id, business_domain, source_language, target_language, term)
);

CREATE INDEX IF NOT EXISTS idx_workspace_glossaries_lookup ON workspace.workspace_knowledge_glossaries (workspace_id, business_domain, source_language);
