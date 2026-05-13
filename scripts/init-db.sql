CREATE EXTENSION IF NOT EXISTS "uuid-ossp";





-- SQL dump generated using DBML (dbml.dbdiagram.io)
-- Database: PostgreSQL
-- Generated at: 2026-05-13T05:08:12.231Z

CREATE SCHEMA auth;

CREATE SCHEMA translation_room;

CREATE SCHEMA transcript;

CREATE SCHEMA ai;

CREATE SCHEMA voice;

CREATE SCHEMA subscription;

CREATE SCHEMA notification;

CREATE SCHEMA integration;

CREATE SCHEMA privacy;

CREATE SCHEMA platform;

CREATE SCHEMA admin;

CREATE TYPE room_status AS ENUM (
  'SCHEDULED',
  'WAITING',
  'IN_PROGRESS',
  'PAUSED',
  'ENDED',
  'CANCELLED',
  'EXPIRED',
  'FAILED'
);

CREATE TYPE participant_status AS ENUM (
  'INVITED',
  'WAITING',
  'CONNECTED',
  'DISCONNECTED',
  'LEFT',
  'KICKED',
  'REJECTED'
);

CREATE TYPE job_status AS ENUM (
  'QUEUED',
  'PROCESSING',
  'COMPLETED',
  'FAILED',
  'CANCELLED'
);

CREATE TYPE consent_status AS ENUM (
  'GRANTED',
  'REVOKED',
  'EXPIRED'
);

CREATE TYPE artifact_type AS ENUM (
  'TRANSCRIPT_EXPORT',
  'SUMMARY_EXPORT',
  'DEBUG_LOG',
  'OPTIONAL_RECORDING',
  'AUDIO_SAMPLE'
);

CREATE TYPE notification_status AS ENUM (
  'PENDING',
  'SENT',
  'DELIVERED',
  'FAILED',
  'READ'
);

CREATE TYPE ticket_status AS ENUM (
  'OPEN',
  'IN_PROGRESS',
  'RESOLVED',
  'CLOSED'
);

CREATE TABLE auth.users (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  email VARCHAR(320) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  full_name VARCHAR(150) NOT NULL,
  avatar_url VARCHAR(500),
  phone VARCHAR(20),
  preferred_language VARCHAR(15) NOT NULL DEFAULT 'vi-VN',
  timezone VARCHAR(50) NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_locked BOOLEAN NOT NULL DEFAULT false,
  failed_login_attempts INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  email_verified BOOLEAN NOT NULL DEFAULT false,
  email_verified_at TIMESTAMPTZ,
  google_id VARCHAR(255) UNIQUE,
  last_login_at TIMESTAMPTZ,
  last_login_ip VARCHAR(45),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE auth.roles (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  name VARCHAR(50) UNIQUE NOT NULL,
  description VARCHAR(255),
  is_system BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE auth.permissions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  code VARCHAR(100) UNIQUE NOT NULL,
  description VARCHAR(255),
  group_name VARCHAR(50) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE auth.role_permissions (
  role_id UUID NOT NULL,
  permission_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE auth.user_roles (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  role_id UUID NOT NULL,
  workspace_id UUID,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  assigned_by UUID,
  revoked_at TIMESTAMPTZ,
  revoked_by UUID
);

CREATE TABLE auth.workspaces (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  name VARCHAR(150) NOT NULL,
  slug VARCHAR(100) UNIQUE NOT NULL,
  owner_id UUID NOT NULL,
  logo_url VARCHAR(500),
  plan_tier VARCHAR(30) NOT NULL DEFAULT 'free',
  settings JSONB NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE auth.workspace_members (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role_id UUID NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  removed_at TIMESTAMPTZ,
  removed_by UUID
);

CREATE TABLE auth.workspace_invitations (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  email VARCHAR(320) NOT NULL,
  role_id UUID NOT NULL,
  invited_by UUID NOT NULL,
  token_hash VARCHAR(255) UNIQUE NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  expires_at TIMESTAMPTZ NOT NULL,
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE auth.refresh_tokens (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  token_hash VARCHAR(255) UNIQUE NOT NULL,
  device_info VARCHAR(255),
  ip_address VARCHAR(45),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE auth.user_settings (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID UNIQUE NOT NULL,
  default_speak_language VARCHAR(15) NOT NULL DEFAULT 'vi-VN',
  default_listen_language VARCHAR(15) NOT NULL DEFAULT 'en-US',
  voice_clone_enabled BOOLEAN NOT NULL DEFAULT false,
  mic_noise_suppression BOOLEAN NOT NULL DEFAULT true,
  default_translation_room_type VARCHAR(20) NOT NULL DEFAULT 'group',
  auto_record_translation_rooms BOOLEAN NOT NULL DEFAULT false,
  auto_generate_summary BOOLEAN NOT NULL DEFAULT true,
  default_max_participants INT NOT NULL DEFAULT 10,
  theme VARCHAR(10) NOT NULL DEFAULT 'system',
  transcript_font_size INT NOT NULL DEFAULT 14,
  show_original_transcript BOOLEAN NOT NULL DEFAULT true,
  show_translated_transcript BOOLEAN NOT NULL DEFAULT true,
  high_contrast BOOLEAN NOT NULL DEFAULT false,
  screen_reader_mode BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID
);

CREATE TABLE auth.schema_migrations (
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

CREATE TABLE translation_room.translation_rooms (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  host_id UUID NOT NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  translation_room_code VARCHAR(12) UNIQUE NOT NULL,
  status room_status NOT NULL DEFAULT 'SCHEDULED',
  translation_room_type VARCHAR(20) NOT NULL DEFAULT 'group',
  max_participants INT NOT NULL DEFAULT 10,
  source_language VARCHAR(15) NOT NULL,
  target_languages JSONB NOT NULL DEFAULT '[]',
  settings JSONB NOT NULL DEFAULT '{}',
  scheduled_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  duration_seconds INT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE translation_room.translation_room_participants (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  translation_room_id UUID NOT NULL,
  user_id UUID,
  display_name VARCHAR(100) NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'participant',
  listen_language VARCHAR(15) NOT NULL,
  speak_language VARCHAR(15) NOT NULL,
  status participant_status NOT NULL DEFAULT 'INVITED',
  connection_type VARCHAR(20) NOT NULL DEFAULT 'webrtc',
  is_muted BOOLEAN NOT NULL DEFAULT false,
  is_using_voice_clone BOOLEAN NOT NULL DEFAULT false,
  joined_at TIMESTAMPTZ,
  left_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE translation_room.translation_room_audio_routes (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  translation_room_id UUID NOT NULL,
  source_participant_id UUID NOT NULL,
  target_participant_id UUID NOT NULL,
  source_language VARCHAR(15) NOT NULL,
  target_language VARCHAR(15) NOT NULL,
  voice_clone_enabled BOOLEAN NOT NULL DEFAULT false,
  stream_id VARCHAR(100),
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  started_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE translation_room.translation_room_artifacts (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  translation_room_id UUID NOT NULL,
  artifact_type artifact_type NOT NULL,
  file_url VARCHAR(500),
  file_format VARCHAR(20),
  file_size_bytes BIGINT,
  contains_raw_audio BOOLEAN NOT NULL DEFAULT false,
  contains_raw_video BOOLEAN NOT NULL DEFAULT false,
  consent_required BOOLEAN NOT NULL DEFAULT false,
  retention_until TIMESTAMPTZ,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE translation_room.translation_room_feedback (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  translation_room_id UUID NOT NULL,
  user_id UUID NOT NULL,
  overall_rating INT NOT NULL,
  translation_quality INT,
  audio_quality INT,
  voice_clone_quality INT,
  ai_summary_quality INT,
  comments TEXT,
  communication_insights JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE translation_room.schema_migrations (
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

CREATE TABLE transcript.transcripts (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  translation_room_id UUID NOT NULL,
  version INT NOT NULL DEFAULT 1,
  status VARCHAR(20) NOT NULL DEFAULT 'recording',
  source_language VARCHAR(15) NOT NULL,
  total_segments INT NOT NULL DEFAULT 0,
  total_duration_ms INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  finalized_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE transcript.transcript_segments (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  transcript_id UUID NOT NULL,
  speaker_participant_id UUID,
  speaker_name VARCHAR(100) NOT NULL,
  original_text TEXT NOT NULL,
  original_language VARCHAR(15) NOT NULL,
  start_time_ms INT NOT NULL,
  end_time_ms INT NOT NULL,
  confidence DECIMAL(5,4),
  sequence_order INT NOT NULL,
  is_corrected BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE transcript.transcript_translations (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  segment_id UUID NOT NULL,
  target_language VARCHAR(15) NOT NULL,
  translated_text TEXT NOT NULL,
  translator_model VARCHAR(100) NOT NULL,
  confidence DECIMAL(5,4),
  is_retranslated BOOLEAN NOT NULL DEFAULT false,
  latency_ms INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE transcript.transcript_corrections (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  segment_id UUID NOT NULL,
  user_id UUID NOT NULL,
  original_text TEXT NOT NULL,
  corrected_text TEXT NOT NULL,
  correction_type VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'accepted',
  triggered_retranslation BOOLEAN NOT NULL DEFAULT false,
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE transcript.transcript_exports (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  transcript_id UUID NOT NULL,
  user_id UUID NOT NULL,
  format VARCHAR(10) NOT NULL,
  file_url VARCHAR(500) NOT NULL,
  included_languages JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE transcript.glossaries (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  name VARCHAR(150) NOT NULL,
  description TEXT,
  source_language VARCHAR(15) NOT NULL,
  target_language VARCHAR(15) NOT NULL,
  term_count INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE transcript.glossary_terms (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  glossary_id UUID NOT NULL,
  source_term VARCHAR(255) NOT NULL,
  target_term VARCHAR(255) NOT NULL,
  context TEXT,
  domain VARCHAR(50),
  priority INT NOT NULL DEFAULT 5,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE transcript.schema_migrations (
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

CREATE TABLE ai.processing_jobs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  translation_room_id UUID,
  transcript_id UUID,
  job_type VARCHAR(30) NOT NULL,
  status job_status NOT NULL DEFAULT 'QUEUED',
  priority INT NOT NULL DEFAULT 5,
  input_ref JSONB,
  output_ref JSONB,
  error_code VARCHAR(100),
  error_message TEXT,
  retry_count INT NOT NULL DEFAULT 0,
  queued_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE ai.model_runs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  job_id UUID NOT NULL,
  model_provider VARCHAR(50) NOT NULL,
  model_name VARCHAR(100) NOT NULL,
  model_version VARCHAR(100),
  input_tokens INT,
  output_tokens INT,
  latency_ms INT,
  cost_estimate DECIMAL(12,4),
  success BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE ai.model_metrics (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  model_run_id UUID NOT NULL,
  metric_name VARCHAR(50) NOT NULL,
  metric_value DECIMAL(10,4) NOT NULL,
  language_pair VARCHAR(20),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE ai.prompt_templates (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  name VARCHAR(100) NOT NULL,
  task_type VARCHAR(30) NOT NULL,
  template TEXT NOT NULL,
  version INT NOT NULL DEFAULT 1,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE ai.ai_models (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  provider VARCHAR(50) NOT NULL,
  model_name VARCHAR(100) NOT NULL,
  model_version VARCHAR(100),
  task_type VARCHAR(30) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE ai.model_capabilities (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  model_id UUID NOT NULL,
  source_language VARCHAR(15),
  target_language VARCHAR(15),
  supports_streaming BOOLEAN NOT NULL DEFAULT false,
  supports_voice_clone BOOLEAN NOT NULL DEFAULT false,
  max_latency_target_ms INT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE ai.vector_collections (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  collection_name VARCHAR(100) UNIQUE NOT NULL,
  purpose VARCHAR(50) NOT NULL,
  vector_db_provider VARCHAR(30) NOT NULL DEFAULT 'qdrant',
  embedding_model VARCHAR(100) NOT NULL,
  dimension INT NOT NULL,
  distance_metric VARCHAR(20) NOT NULL DEFAULT 'cosine',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE ai.vector_documents (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  collection_id UUID NOT NULL,
  source_type VARCHAR(50) NOT NULL,
  source_id UUID NOT NULL,
  title VARCHAR(255),
  language VARCHAR(15),
  metadata JSONB NOT NULL DEFAULT '{}',
  indexing_status VARCHAR(20) NOT NULL DEFAULT 'pending',
  indexed_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE ai.vector_chunks (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  vector_document_id UUID NOT NULL,
  source_type VARCHAR(50) NOT NULL,
  source_id UUID,
  chunk_order INT NOT NULL,
  text_preview TEXT,
  qdrant_point_id VARCHAR(100) UNIQUE NOT NULL,
  token_count INT,
  language VARCHAR(15),
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE ai.evaluation_datasets (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID,
  name VARCHAR(150) NOT NULL,
  task_type VARCHAR(30) NOT NULL,
  description TEXT,
  source_language VARCHAR(15),
  target_language VARCHAR(15),
  sample_count INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE ai.evaluation_cases (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  dataset_id UUID NOT NULL,
  case_order INT NOT NULL,
  input_text TEXT,
  expected_output TEXT,
  input_artifact_ref VARCHAR(500),
  expected_metrics JSONB NOT NULL DEFAULT '{}',
  language_pair VARCHAR(20),
  difficulty VARCHAR(20) NOT NULL DEFAULT 'normal',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE ai.schema_migrations (
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

CREATE TABLE voice.voice_profiles (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  workspace_id UUID,
  display_name VARCHAR(100),
  provider VARCHAR(50),
  embedding_ref VARCHAR(500),
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE voice.voice_consents (
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

CREATE TABLE voice.voice_samples (
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

CREATE TABLE voice.schema_migrations (
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

CREATE TABLE subscription.plans (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  name VARCHAR(100) NOT NULL,
  slug VARCHAR(50) UNIQUE NOT NULL,
  tier VARCHAR(20) NOT NULL,
  price DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'VND',
  billing_cycle VARCHAR(20) NOT NULL DEFAULT 'monthly',
  credits_per_cycle INT NOT NULL,
  max_participants INT NOT NULL DEFAULT 2,
  max_languages INT NOT NULL DEFAULT 2,
  voice_clone_enabled BOOLEAN NOT NULL DEFAULT false,
  ai_assistant_enabled BOOLEAN NOT NULL DEFAULT false,
  glossary_enabled BOOLEAN NOT NULL DEFAULT false,
  dedicated_gpu BOOLEAN NOT NULL DEFAULT false,
  features JSONB NOT NULL DEFAULT '{}',
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE subscription.subscriptions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  workspace_id UUID,
  plan_id UUID NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  credits_remaining INT NOT NULL DEFAULT 0,
  credits_used_this_cycle INT NOT NULL DEFAULT 0,
  current_period_start TIMESTAMPTZ NOT NULL,
  current_period_end TIMESTAMPTZ NOT NULL,
  auto_renew BOOLEAN NOT NULL DEFAULT true,
  cancellation_reason TEXT,
  cancelled_at TIMESTAMPTZ,
  trial_ends_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE subscription.credit_transactions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  subscription_id UUID NOT NULL,
  user_id UUID NOT NULL,
  amount INT NOT NULL,
  type VARCHAR(20) NOT NULL,
  description VARCHAR(255),
  reference_id UUID,
  reference_type VARCHAR(30),
  balance_after INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE subscription.credit_balance_snapshots (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  subscription_id UUID NOT NULL,
  credits_remaining INT NOT NULL,
  credits_used_this_cycle INT NOT NULL,
  snapshot_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE subscription.usage_records (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  subscription_id UUID NOT NULL,
  user_id UUID NOT NULL,
  workspace_id UUID,
  translation_room_id UUID,
  usage_type VARCHAR(30) NOT NULL,
  unit VARCHAR(20) NOT NULL DEFAULT 'credit',
  quantity DECIMAL(12,4) NOT NULL DEFAULT 1,
  credits_consumed INT NOT NULL,
  duration_seconds INT,
  details JSONB,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE subscription.payments (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  subscription_id UUID NOT NULL,
  user_id UUID NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  tax_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_amount DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'VND',
  payment_method VARCHAR(30) NOT NULL,
  provider VARCHAR(30) NOT NULL DEFAULT 'payos',
  provider_transaction_id VARCHAR(255) UNIQUE,
  provider_order_id VARCHAR(255),
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  failure_reason VARCHAR(500),
  provider_metadata JSONB,
  paid_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE subscription.refunds (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  payment_id UUID NOT NULL,
  user_id UUID NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  reason VARCHAR(500),
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  provider_refund_id VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  completed_at TIMESTAMPTZ
);

CREATE TABLE subscription.invoices (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  payment_id UUID NOT NULL,
  user_id UUID NOT NULL,
  invoice_number VARCHAR(30) UNIQUE NOT NULL,
  subtotal DECIMAL(12,2) NOT NULL,
  tax DECIMAL(12,2) NOT NULL DEFAULT 0,
  total DECIMAL(12,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'VND',
  status VARCHAR(20) NOT NULL DEFAULT 'issued',
  pdf_url VARCHAR(500),
  line_items JSONB NOT NULL DEFAULT '[]',
  issued_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  due_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE subscription.schema_migrations (
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

CREATE TABLE notification.notification_templates (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  type VARCHAR(50) NOT NULL,
  channel VARCHAR(20) NOT NULL,
  subject VARCHAR(255),
  body_template TEXT NOT NULL,
  variables JSONB NOT NULL DEFAULT '[]',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE notification.notification_campaigns (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  title VARCHAR(255) NOT NULL,
  body TEXT NOT NULL,
  type VARCHAR(50) NOT NULL,
  channel VARCHAR(20) NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  target_audience_mode VARCHAR(50) NOT NULL,
  target_audience_data JSONB NOT NULL DEFAULT '{}',
  status VARCHAR(20) NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  total_targets INT NOT NULL DEFAULT 0,
  success_count INT NOT NULL DEFAULT 0,
  failure_count INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE notification.notifications (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  campaign_id UUID,
  user_id UUID NOT NULL,
  workspace_id UUID,
  type VARCHAR(50) NOT NULL,
  channel VARCHAR(20) NOT NULL,
  title VARCHAR(255) NOT NULL,
  body TEXT NOT NULL,
  data JSONB,
  priority VARCHAR(10) NOT NULL DEFAULT 'normal',
  status notification_status NOT NULL DEFAULT 'PENDING',
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE notification.email_delivery_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  notification_id UUID NOT NULL,
  to_email VARCHAR(320) NOT NULL,
  subject VARCHAR(255) NOT NULL,
  provider VARCHAR(30) NOT NULL,
  provider_message_id VARCHAR(255),
  status VARCHAR(20) NOT NULL DEFAULT 'queued',
  failure_reason VARCHAR(500),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  bounced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE notification.push_subscriptions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  device_token VARCHAR(500) UNIQUE NOT NULL,
  platform VARCHAR(20) NOT NULL,
  device_name VARCHAR(100),
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE notification.push_delivery_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  notification_id UUID NOT NULL,
  push_subscription_id UUID,
  provider VARCHAR(30) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'queued',
  failure_reason VARCHAR(500),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE notification.notification_preferences (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  notification_type VARCHAR(50) NOT NULL,
  email_enabled BOOLEAN NOT NULL DEFAULT true,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  in_app_enabled BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID
);

CREATE TABLE notification.schema_migrations (
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

CREATE TABLE integration.external_platform_accounts (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  provider VARCHAR(30) NOT NULL,
  provider_account_id VARCHAR(255),
  access_token_ref VARCHAR(500),
  refresh_token_ref VARCHAR(500),
  token_expires_at TIMESTAMPTZ,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE integration.external_meeting_sessions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  translation_room_id UUID NOT NULL,
  provider VARCHAR(30) NOT NULL,
  external_meeting_id VARCHAR(255),
  meeting_url VARCHAR(500),
  capture_mode VARCHAR(30) NOT NULL,
  connection_status VARCHAR(20) NOT NULL DEFAULT 'disconnected',
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE integration.webhook_endpoints (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  name VARCHAR(100) NOT NULL,
  target_url VARCHAR(500) NOT NULL,
  secret_ref VARCHAR(500),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE integration.webhook_events (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  endpoint_id UUID NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  retry_count INT NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  delivered_at TIMESTAMPTZ
);

CREATE TABLE integration.integration_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  provider VARCHAR(30) NOT NULL,
  user_id UUID,
  workspace_id UUID,
  action VARCHAR(100) NOT NULL,
  status VARCHAR(20) NOT NULL,
  request_id VARCHAR(100),
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE integration.schema_migrations (
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

CREATE TABLE privacy.consent_records (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  workspace_id UUID,
  consent_type VARCHAR(50) NOT NULL,
  consent_status consent_status NOT NULL,
  consent_text_version VARCHAR(50) NOT NULL,
  granted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE privacy.data_retention_policies (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID,
  data_type VARCHAR(50) NOT NULL,
  retention_days INT NOT NULL,
  auto_delete_enabled BOOLEAN NOT NULL DEFAULT true,
  requires_consent BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE privacy.data_deletion_requests (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  workspace_id UUID,
  request_type VARCHAR(50) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  processed_at TIMESTAMPTZ,
  processed_by UUID,
  notes TEXT
);

CREATE TABLE privacy.data_access_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID,
  workspace_id UUID,
  accessed_by UUID NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id UUID NOT NULL,
  access_reason VARCHAR(255),
  ip_address VARCHAR(45),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE privacy.policy_versions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  policy_type VARCHAR(50) NOT NULL,
  version VARCHAR(50) NOT NULL,
  title VARCHAR(255) NOT NULL,
  content TEXT NOT NULL,
  effective_at TIMESTAMPTZ NOT NULL,
  retired_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID
);

CREATE TABLE privacy.data_processing_records (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID,
  user_id UUID,
  processing_type VARCHAR(50) NOT NULL,
  data_type VARCHAR(50) NOT NULL,
  legal_basis VARCHAR(100),
  purpose VARCHAR(255) NOT NULL,
  processor_service VARCHAR(50) NOT NULL,
  source_entity_type VARCHAR(50),
  source_entity_id UUID,
  started_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  completed_at TIMESTAMPTZ,
  status VARCHAR(20) NOT NULL DEFAULT 'processing',
  metadata JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE privacy.schema_migrations (
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

CREATE TABLE platform.supported_languages (
  code VARCHAR(15) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  native_name VARCHAR(100),
  stt_supported BOOLEAN NOT NULL DEFAULT false,
  translation_supported BOOLEAN NOT NULL DEFAULT false,
  tts_supported BOOLEAN NOT NULL DEFAULT false,
  voice_clone_supported BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE platform.system_configurations (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  key VARCHAR(100) UNIQUE NOT NULL,
  value JSONB NOT NULL,
  description VARCHAR(500),
  is_sensitive BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE platform.feature_flags (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  key VARCHAR(100) UNIQUE NOT NULL,
  description VARCHAR(500),
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  rollout_percentage INT NOT NULL DEFAULT 0,
  conditions JSONB NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE platform.service_configurations (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  service_name VARCHAR(50) NOT NULL,
  config_key VARCHAR(100) NOT NULL,
  config_value JSONB NOT NULL,
  is_sensitive BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE platform.config_change_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  config_scope VARCHAR(50) NOT NULL,
  config_key VARCHAR(100) NOT NULL,
  old_value JSONB,
  new_value JSONB,
  changed_by UUID,
  change_reason VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE platform.audit_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID,
  workspace_id UUID,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id UUID,
  old_values JSONB,
  new_values JSONB,
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE platform.security_events (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID,
  event_type VARCHAR(50) NOT NULL,
  severity VARCHAR(20) NOT NULL DEFAULT 'medium',
  ip_address VARCHAR(45),
  user_agent VARCHAR(500),
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE platform.activity_logs (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID,
  workspace_id UUID,
  activity_type VARCHAR(50) NOT NULL,
  description VARCHAR(500),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE platform.outbox_events (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  aggregate_type VARCHAR(50) NOT NULL,
  aggregate_id UUID NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  retry_count INT NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  published_at TIMESTAMPTZ
);

CREATE TABLE platform.inbox_events (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  source_service VARCHAR(50) NOT NULL,
  event_id UUID NOT NULL,
  event_type VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'received',
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  received_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE platform.service_health_checks (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  service_name VARCHAR(50) NOT NULL,
  status VARCHAR(20) NOT NULL,
  version VARCHAR(50),
  latency_ms INT,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  details JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE platform.service_deployments (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  service_name VARCHAR(50) NOT NULL,
  version VARCHAR(50) NOT NULL,
  environment VARCHAR(30) NOT NULL DEFAULT 'production',
  deployed_by UUID,
  deployed_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  status VARCHAR(20) NOT NULL DEFAULT 'deployed',
  notes TEXT
);

CREATE TABLE platform.schema_migrations (
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

CREATE TABLE admin.admin_actions (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  admin_user_id UUID NOT NULL,
  target_user_id UUID,
  workspace_id UUID,
  action VARCHAR(100) NOT NULL,
  reason VARCHAR(500),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE TABLE admin.support_tickets (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  user_id UUID NOT NULL,
  workspace_id UUID,
  subject VARCHAR(255) NOT NULL,
  description TEXT NOT NULL,
  status ticket_status NOT NULL DEFAULT 'OPEN',
  priority VARCHAR(20) NOT NULL DEFAULT 'normal',
  assigned_to UUID,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  resolved_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE admin.support_ticket_comments (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  support_ticket_id UUID NOT NULL,
  author_user_id UUID NOT NULL,
  comment TEXT NOT NULL,
  is_internal BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE admin.incident_reports (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  title VARCHAR(255) NOT NULL,
  severity VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  affected_service VARCHAR(50),
  description TEXT,
  started_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE admin.maintenance_windows (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end TIMESTAMPTZ NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

CREATE TABLE admin.schema_migrations (
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

CREATE UNIQUE INDEX ON auth.user_roles (user_id, role_id, workspace_id);

CREATE UNIQUE INDEX ON auth.workspace_members (workspace_id, user_id);

CREATE INDEX ON auth.workspace_invitations (workspace_id, email);

CREATE INDEX ON auth.schema_migrations (status);

CREATE INDEX ON translation_room.translation_rooms (workspace_id, created_at);

CREATE INDEX ON translation_room.translation_rooms (host_id, created_at);

CREATE INDEX ON translation_room.translation_rooms (status, scheduled_at);

CREATE INDEX ON translation_room.translation_room_participants (translation_room_id, user_id);

CREATE INDEX ON translation_room.translation_room_participants (translation_room_id, status);

CREATE INDEX ON translation_room.translation_room_audio_routes (translation_room_id, status);

CREATE INDEX ON translation_room.translation_room_audio_routes (source_participant_id, target_participant_id);

CREATE INDEX ON translation_room.translation_room_artifacts (translation_room_id, artifact_type);

CREATE INDEX ON translation_room.translation_room_artifacts (retention_until);

CREATE UNIQUE INDEX ON translation_room.translation_room_feedback (translation_room_id, user_id);

CREATE INDEX ON translation_room.schema_migrations (status);

CREATE UNIQUE INDEX ON transcript.transcripts (translation_room_id, version);

CREATE INDEX ON transcript.transcripts (workspace_id, created_at);

CREATE UNIQUE INDEX ON transcript.transcript_segments (transcript_id, sequence_order);

CREATE INDEX ON transcript.transcript_segments (speaker_participant_id);

CREATE UNIQUE INDEX ON transcript.transcript_translations (segment_id, target_language);

CREATE UNIQUE INDEX ON transcript.glossaries (workspace_id, name);

CREATE UNIQUE INDEX ON transcript.glossary_terms (glossary_id, source_term);

CREATE INDEX ON transcript.schema_migrations (status);

CREATE INDEX ON ai.processing_jobs (workspace_id, created_at);

CREATE INDEX ON ai.processing_jobs (translation_room_id, job_type);

CREATE INDEX ON ai.processing_jobs (status, priority);

CREATE UNIQUE INDEX ON ai.ai_models (provider, model_name, model_version, task_type);

CREATE INDEX ON ai.vector_documents (workspace_id, source_type, source_id);

CREATE INDEX ON ai.vector_documents (collection_id, indexing_status);

CREATE UNIQUE INDEX ON ai.vector_chunks (vector_document_id, chunk_order);

CREATE INDEX ON ai.vector_chunks (source_type, source_id);

CREATE INDEX ON ai.evaluation_datasets (workspace_id, task_type);

CREATE UNIQUE INDEX ON ai.evaluation_datasets (name, task_type);

CREATE UNIQUE INDEX ON ai.evaluation_cases (dataset_id, case_order);

CREATE INDEX ON ai.schema_migrations (status);

CREATE INDEX ON voice.voice_profiles (user_id, status);

CREATE INDEX ON voice.voice_profiles (workspace_id);

CREATE INDEX ON voice.schema_migrations (status);

CREATE INDEX ON subscription.credit_transactions (subscription_id, created_at);

CREATE INDEX ON subscription.usage_records (subscription_id, recorded_at);

CREATE INDEX ON subscription.usage_records (translation_room_id);

CREATE INDEX ON subscription.schema_migrations (status);

CREATE UNIQUE INDEX ON notification.notification_templates (type, channel);

CREATE INDEX ON notification.notification_campaigns (status, scheduled_at);

CREATE INDEX ON notification.notification_campaigns (type, created_at);

CREATE INDEX ON notification.notification_campaigns (created_by);

CREATE INDEX ON notification.notifications (campaign_id);

CREATE INDEX ON notification.notifications (user_id, created_at);

CREATE INDEX ON notification.notifications (status, scheduled_at);

CREATE UNIQUE INDEX ON notification.notification_preferences (user_id, notification_type);

CREATE INDEX ON notification.schema_migrations (status);

CREATE UNIQUE INDEX ON integration.external_platform_accounts (user_id, provider);

CREATE INDEX ON integration.schema_migrations (status);

CREATE INDEX ON privacy.consent_records (user_id, consent_type, created_at);

CREATE INDEX ON privacy.data_access_logs (entity_type, entity_id);

CREATE INDEX ON privacy.data_access_logs (accessed_by, created_at);

CREATE UNIQUE INDEX ON privacy.policy_versions (policy_type, version);

CREATE INDEX ON privacy.policy_versions (policy_type, is_active);

CREATE INDEX ON privacy.data_processing_records (workspace_id, started_at);

CREATE INDEX ON privacy.data_processing_records (user_id, started_at);

CREATE INDEX ON privacy.data_processing_records (processing_type, status);

CREATE INDEX ON privacy.schema_migrations (status);

CREATE UNIQUE INDEX ON platform.service_configurations (service_name, config_key);

CREATE INDEX ON platform.audit_logs (entity_type, entity_id);

CREATE INDEX ON platform.audit_logs (user_id, created_at);

CREATE INDEX ON platform.security_events (user_id, created_at);

CREATE INDEX ON platform.security_events (event_type, created_at);

CREATE INDEX ON platform.activity_logs (workspace_id, created_at);

CREATE INDEX ON platform.activity_logs (user_id, created_at);

CREATE INDEX ON platform.outbox_events (status, created_at);

CREATE INDEX ON platform.outbox_events (aggregate_type, aggregate_id);

CREATE UNIQUE INDEX ON platform.inbox_events (source_service, event_id);

CREATE INDEX ON platform.inbox_events (status, received_at);

CREATE INDEX ON platform.service_health_checks (service_name, checked_at);

CREATE INDEX ON platform.service_health_checks (status, checked_at);

CREATE INDEX ON platform.service_deployments (service_name, deployed_at);

CREATE INDEX ON platform.service_deployments (environment, status);

CREATE INDEX ON platform.schema_migrations (status);

CREATE INDEX ON admin.support_ticket_comments (support_ticket_id, created_at);

CREATE INDEX ON admin.schema_migrations (status);

COMMENT ON COLUMN auth.users.created_by IS 'Internal auth user reference. Nullable for system-created users.';

COMMENT ON COLUMN auth.users.updated_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.users.deleted_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.roles.created_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.roles.updated_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.roles.deleted_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.permissions.created_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.permissions.updated_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.permissions.deleted_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.role_permissions.created_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.user_roles.workspace_id IS 'Internal AuthService workspace reference. Nullable for global roles.';

COMMENT ON COLUMN auth.user_roles.assigned_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.user_roles.revoked_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.workspaces.owner_id IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.workspaces.created_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.workspaces.updated_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.workspaces.deleted_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.workspace_members.removed_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.workspace_invitations.invited_by IS 'Internal auth user reference.';

COMMENT ON COLUMN auth.user_settings.updated_by IS 'Internal auth user reference.';

COMMENT ON TABLE translation_room.translation_rooms IS 'Room lifecycle:
SCHEDULED -> WAITING
SCHEDULED -> CANCELLED
SCHEDULED -> EXPIRED
WAITING -> IN_PROGRESS
WAITING -> CANCELLED
WAITING -> EXPIRED
IN_PROGRESS -> PAUSED
PAUSED -> IN_PROGRESS
IN_PROGRESS -> ENDED
IN_PROGRESS -> FAILED

Draft room is not persisted. If the user discards a draft, no room record is created.
';

COMMENT ON COLUMN translation_room.translation_rooms.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN translation_room.translation_rooms.host_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN translation_room.translation_rooms.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN translation_room.translation_rooms.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN translation_room.translation_rooms.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON TABLE translation_room.translation_room_participants IS 'Participant lifecycle:
INVITED -> WAITING
WAITING -> CONNECTED
WAITING -> REJECTED
CONNECTED -> DISCONNECTED
DISCONNECTED -> CONNECTED
CONNECTED -> LEFT
CONNECTED -> KICKED

MUTED is not a participant_status. It is represented by is_muted.
';

COMMENT ON COLUMN translation_room.translation_room_participants.user_id IS 'External AuthService user id. Nullable for guests. No physical FK.';

COMMENT ON COLUMN translation_room.translation_room_artifacts.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN translation_room.translation_room_artifacts.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN translation_room.translation_room_feedback.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.transcripts.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN transcript.transcripts.translation_room_id IS 'External TranslationRoomService room id. No physical FK.';

COMMENT ON COLUMN transcript.transcripts.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.transcripts.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.transcripts.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.transcript_segments.speaker_participant_id IS 'External TranslationRoomService participant id. No physical FK.';

COMMENT ON COLUMN transcript.transcript_corrections.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.transcript_corrections.reviewed_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.transcript_exports.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.glossaries.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN transcript.glossaries.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.glossaries.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.glossaries.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.glossary_terms.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.glossary_terms.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN transcript.glossary_terms.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.processing_jobs.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN ai.processing_jobs.translation_room_id IS 'External TranslationRoomService room id. No physical FK.';

COMMENT ON COLUMN ai.processing_jobs.transcript_id IS 'External TranscriptService transcript id. No physical FK.';

COMMENT ON COLUMN ai.prompt_templates.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.prompt_templates.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.prompt_templates.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.ai_models.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.ai_models.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.ai_models.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.model_capabilities.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.model_capabilities.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.model_capabilities.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_collections.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN ai.vector_collections.collection_name IS 'Qdrant collection name.';

COMMENT ON COLUMN ai.vector_collections.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_collections.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_collections.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_documents.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN ai.vector_documents.source_type IS 'transcript, transcript_segment, summary, action_item, glossary_term, etc.';

COMMENT ON COLUMN ai.vector_documents.source_id IS 'External source object id. No physical FK.';

COMMENT ON COLUMN ai.vector_documents.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_documents.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_documents.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.vector_chunks.source_id IS 'External source object id. No physical FK.';

COMMENT ON COLUMN ai.evaluation_datasets.workspace_id IS 'External AuthService workspace id. No physical FK. Null means global benchmark dataset.';

COMMENT ON COLUMN ai.evaluation_datasets.task_type IS 'stt, translation, tts, summary, action_items, qa';

COMMENT ON COLUMN ai.evaluation_datasets.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.evaluation_datasets.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN ai.evaluation_datasets.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN voice.voice_profiles.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN voice.voice_profiles.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN voice.voice_profiles.embedding_ref IS 'Reference to voice embedding/model storage, not raw audio.';

COMMENT ON COLUMN voice.voice_profiles.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN voice.voice_profiles.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN voice.voice_profiles.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN voice.voice_consents.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN voice.voice_samples.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.plans.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.plans.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.plans.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.subscriptions.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.subscriptions.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN subscription.subscriptions.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.subscriptions.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.subscriptions.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.credit_transactions.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.credit_transactions.reference_id IS 'External business object id such as room/job/payment. No physical FK.';

COMMENT ON COLUMN subscription.usage_records.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.usage_records.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN subscription.usage_records.translation_room_id IS 'External TranslationRoomService room id. No physical FK.';

COMMENT ON COLUMN subscription.payments.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.refunds.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN subscription.invoices.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_templates.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_templates.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_templates.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_campaigns.channel IS 'in_app, email, push, all';

COMMENT ON COLUMN notification.notification_campaigns.target_audience_mode IS 'all_users, workspace, plan_tier, role, custom_users, active_users';

COMMENT ON COLUMN notification.notification_campaigns.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_campaigns.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_campaigns.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notifications.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notifications.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN notification.push_subscriptions.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.push_subscriptions.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.push_subscriptions.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.push_subscriptions.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_preferences.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN notification.notification_preferences.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.external_platform_accounts.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.external_platform_accounts.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.external_platform_accounts.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.external_platform_accounts.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.external_meeting_sessions.translation_room_id IS 'External TranslationRoomService room id. No physical FK.';

COMMENT ON COLUMN integration.webhook_endpoints.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN integration.webhook_endpoints.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.webhook_endpoints.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.webhook_endpoints.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.integration_logs.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN integration.integration_logs.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN privacy.consent_records.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.consent_records.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN privacy.data_retention_policies.workspace_id IS 'External AuthService workspace id. No physical FK. Null means global policy.';

COMMENT ON COLUMN privacy.data_retention_policies.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_retention_policies.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_retention_policies.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_deletion_requests.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_deletion_requests.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN privacy.data_deletion_requests.processed_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_access_logs.user_id IS 'External AuthService user id whose data was accessed. No physical FK.';

COMMENT ON COLUMN privacy.data_access_logs.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN privacy.data_access_logs.accessed_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_access_logs.entity_id IS 'External business object id. No physical FK.';

COMMENT ON COLUMN privacy.policy_versions.policy_type IS 'privacy_policy, terms_of_service, voice_consent, ai_processing_notice';

COMMENT ON COLUMN privacy.policy_versions.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.policy_versions.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_processing_records.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN privacy.data_processing_records.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN privacy.data_processing_records.processing_type IS 'audio_processing, transcription, translation, voice_clone, summary, vector_indexing';

COMMENT ON COLUMN privacy.data_processing_records.source_entity_id IS 'External business object id. No physical FK.';

COMMENT ON COLUMN platform.supported_languages.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.supported_languages.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.supported_languages.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.system_configurations.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.system_configurations.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.system_configurations.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.feature_flags.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.feature_flags.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.feature_flags.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.service_configurations.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.service_configurations.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.service_configurations.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.config_change_logs.changed_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.audit_logs.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.audit_logs.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN platform.audit_logs.entity_id IS 'External business object id. No physical FK.';

COMMENT ON COLUMN platform.security_events.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.activity_logs.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN platform.activity_logs.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN platform.service_deployments.deployed_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.admin_actions.admin_user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.admin_actions.target_user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.admin_actions.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN admin.support_tickets.user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.support_tickets.workspace_id IS 'External AuthService workspace id. No physical FK.';

COMMENT ON COLUMN admin.support_tickets.assigned_to IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.support_tickets.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.support_tickets.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.support_tickets.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.support_ticket_comments.author_user_id IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.incident_reports.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.incident_reports.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.incident_reports.deleted_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.maintenance_windows.created_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.maintenance_windows.updated_by IS 'External AuthService user id. No physical FK.';

COMMENT ON COLUMN admin.maintenance_windows.deleted_by IS 'External AuthService user id. No physical FK.';

ALTER TABLE auth.users ADD FOREIGN KEY (created_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.users ADD FOREIGN KEY (updated_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.users ADD FOREIGN KEY (deleted_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.roles ADD FOREIGN KEY (created_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.roles ADD FOREIGN KEY (updated_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.roles ADD FOREIGN KEY (deleted_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.permissions ADD FOREIGN KEY (created_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.permissions ADD FOREIGN KEY (updated_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.permissions ADD FOREIGN KEY (deleted_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.role_permissions ADD FOREIGN KEY (role_id) REFERENCES auth.roles (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.role_permissions ADD FOREIGN KEY (permission_id) REFERENCES auth.permissions (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.role_permissions ADD FOREIGN KEY (created_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.user_roles ADD FOREIGN KEY (user_id) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.user_roles ADD FOREIGN KEY (role_id) REFERENCES auth.roles (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.user_roles ADD FOREIGN KEY (workspace_id) REFERENCES auth.workspaces (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.user_roles ADD FOREIGN KEY (assigned_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.user_roles ADD FOREIGN KEY (revoked_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspaces ADD FOREIGN KEY (owner_id) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspaces ADD FOREIGN KEY (created_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspaces ADD FOREIGN KEY (updated_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspaces ADD FOREIGN KEY (deleted_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_members ADD FOREIGN KEY (workspace_id) REFERENCES auth.workspaces (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_members ADD FOREIGN KEY (user_id) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_members ADD FOREIGN KEY (role_id) REFERENCES auth.roles (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_members ADD FOREIGN KEY (removed_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_invitations ADD FOREIGN KEY (workspace_id) REFERENCES auth.workspaces (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_invitations ADD FOREIGN KEY (role_id) REFERENCES auth.roles (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.workspace_invitations ADD FOREIGN KEY (invited_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.refresh_tokens ADD FOREIGN KEY (user_id) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.users ADD FOREIGN KEY (id) REFERENCES auth.user_settings (user_id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE auth.user_settings ADD FOREIGN KEY (updated_by) REFERENCES auth.users (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE translation_room.translation_room_participants ADD FOREIGN KEY (translation_room_id) REFERENCES translation_room.translation_rooms (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE translation_room.translation_room_audio_routes ADD FOREIGN KEY (translation_room_id) REFERENCES translation_room.translation_rooms (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE translation_room.translation_room_audio_routes ADD FOREIGN KEY (source_participant_id) REFERENCES translation_room.translation_room_participants (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE translation_room.translation_room_audio_routes ADD FOREIGN KEY (target_participant_id) REFERENCES translation_room.translation_room_participants (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE translation_room.translation_room_artifacts ADD FOREIGN KEY (translation_room_id) REFERENCES translation_room.translation_rooms (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE translation_room.translation_room_feedback ADD FOREIGN KEY (translation_room_id) REFERENCES translation_room.translation_rooms (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE transcript.transcript_segments ADD FOREIGN KEY (transcript_id) REFERENCES transcript.transcripts (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE transcript.transcript_translations ADD FOREIGN KEY (segment_id) REFERENCES transcript.transcript_segments (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE transcript.transcript_corrections ADD FOREIGN KEY (segment_id) REFERENCES transcript.transcript_segments (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE transcript.transcript_exports ADD FOREIGN KEY (transcript_id) REFERENCES transcript.transcripts (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE transcript.glossary_terms ADD FOREIGN KEY (glossary_id) REFERENCES transcript.glossaries (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE ai.model_runs ADD FOREIGN KEY (job_id) REFERENCES ai.processing_jobs (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE ai.model_metrics ADD FOREIGN KEY (model_run_id) REFERENCES ai.model_runs (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE ai.model_capabilities ADD FOREIGN KEY (model_id) REFERENCES ai.ai_models (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE ai.vector_documents ADD FOREIGN KEY (collection_id) REFERENCES ai.vector_collections (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE ai.vector_chunks ADD FOREIGN KEY (vector_document_id) REFERENCES ai.vector_documents (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE ai.evaluation_cases ADD FOREIGN KEY (dataset_id) REFERENCES ai.evaluation_datasets (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE voice.voice_consents ADD FOREIGN KEY (voice_profile_id) REFERENCES voice.voice_profiles (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE voice.voice_samples ADD FOREIGN KEY (voice_profile_id) REFERENCES voice.voice_profiles (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.subscriptions ADD FOREIGN KEY (plan_id) REFERENCES subscription.plans (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.credit_transactions ADD FOREIGN KEY (subscription_id) REFERENCES subscription.subscriptions (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.credit_balance_snapshots ADD FOREIGN KEY (subscription_id) REFERENCES subscription.subscriptions (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.usage_records ADD FOREIGN KEY (subscription_id) REFERENCES subscription.subscriptions (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.payments ADD FOREIGN KEY (subscription_id) REFERENCES subscription.subscriptions (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.refunds ADD FOREIGN KEY (payment_id) REFERENCES subscription.payments (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE subscription.invoices ADD FOREIGN KEY (payment_id) REFERENCES subscription.payments (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE notification.notifications ADD FOREIGN KEY (campaign_id) REFERENCES notification.notification_campaigns (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE notification.email_delivery_logs ADD FOREIGN KEY (notification_id) REFERENCES notification.notifications (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE notification.push_delivery_logs ADD FOREIGN KEY (notification_id) REFERENCES notification.notifications (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE notification.push_delivery_logs ADD FOREIGN KEY (push_subscription_id) REFERENCES notification.push_subscriptions (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE integration.webhook_events ADD FOREIGN KEY (endpoint_id) REFERENCES integration.webhook_endpoints (id) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE admin.support_ticket_comments ADD FOREIGN KEY (support_ticket_id) REFERENCES admin.support_tickets (id) DEFERRABLE INITIALLY IMMEDIATE;
