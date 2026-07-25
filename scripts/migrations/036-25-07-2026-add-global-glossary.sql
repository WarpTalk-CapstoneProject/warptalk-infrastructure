-- Migration: Global glossary — a system-managed term list applied to every workspace,
-- merged (workspace terms always win) into the same stt_prompt/mt_glossary Redis keys
-- GlossaryStartedEventConsumer already publishes per meeting. See
-- docs/global-glossary-plan.md for the full design and rationale.
-- Created At: 2026-07-25
--
-- Lives in transcript.* (not workspace.*) — it's merged alongside transcript.glossaries/
-- glossary_terms in the same consumer, and keeps global data in its own table rather than
-- allowing transcript.glossaries.workspace_id to go NULL (every existing query there filters
-- on workspace_id; a nullable "global" row would silently bypass that filter wherever a
-- caller forgets to exclude it).
--
-- status defaults to 'draft': adding a term must not immediately affect every workspace's
-- live meetings — an explicit publish (status = 'published') is required. Only 'published'
-- rows are read by GlossaryStartedEventConsumer.

CREATE TABLE IF NOT EXISTS transcript.global_glossary_terms (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  term VARCHAR(255) NOT NULL,
  -- Equal to `term` (case-insensitively) ⇒ "keep verbatim, don't translate" — same
  -- convention translation_worker.translator._build_glossary_block already uses for
  -- workspace-level terms.
  preferred_translation VARCHAR(255) NOT NULL,
  source_language VARCHAR(15),   -- NULL = language-agnostic (applies regardless of source)
  target_language VARCHAR(15),   -- NULL = language-agnostic
  business_domain VARCHAR(100),  -- NULL = applies across all domains
  definition TEXT,
  usage_note TEXT,
  priority INT NOT NULL DEFAULT 5,
  status VARCHAR(30) NOT NULL DEFAULT 'draft',
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  created_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_by UUID,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID
);

-- A plain UNIQUE(term, source_language, target_language, business_domain) constraint would
-- NOT dedupe language-agnostic rows (all three NULL) — Postgres treats every NULL as
-- distinct from every other NULL, so two identical language-agnostic "architect" rows
-- would both insert cleanly. COALESCE to empty string first so NULL columns still compare
-- equal to each other.
CREATE UNIQUE INDEX IF NOT EXISTS idx_global_glossary_terms_dedup
  ON transcript.global_glossary_terms (
    lower(term),
    COALESCE(source_language, ''),
    COALESCE(target_language, ''),
    COALESCE(business_domain, '')
  )
  WHERE deleted_at IS NULL;

-- Hot-path index: GlossaryStartedEventConsumer reads only published, non-deleted rows,
-- highest priority first, on every "meeting.started" event.
CREATE INDEX IF NOT EXISTS idx_global_glossary_terms_published
  ON transcript.global_glossary_terms (status, priority DESC)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS transcript.global_glossary_audits (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  term_id UUID NOT NULL,
  action VARCHAR(30) NOT NULL, -- created | updated | published | archived | deleted
  before_json JSONB,
  after_json JSONB,
  actor_user_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

CREATE INDEX IF NOT EXISTS idx_global_glossary_audits_term_id
  ON transcript.global_glossary_audits (term_id);

-- Seed: ~40 English IT/business terms common in Vietnamese-language meetings, pre-published
-- so the merge (GlossaryStartedEventConsumer) has real terms from the moment this migration
-- runs — see docs/global-glossary-plan.md §7 ("skip the admin UI for now, seed via SQL").
-- All language-agnostic (NULL source/target/domain) and "keep verbatim" (preferred_translation
-- == term): these are words Vietnamese teams say in English as-is, not translate.
INSERT INTO transcript.global_glossary_terms
  (term, preferred_translation, priority, status, definition)
VALUES
  ('architect', 'architect', 8, 'published', 'A person or role responsible for the high-level technical design of a system.'),
  ('deploy', 'deploy', 8, 'published', 'To release code/software to a running environment.'),
  ('deployment', 'deployment', 7, 'published', 'The act or process of deploying software.'),
  ('sprint', 'sprint', 8, 'published', 'A fixed, short work cycle in Agile/Scrum project management.'),
  ('backlog', 'backlog', 7, 'published', 'The prioritized list of work not yet completed.'),
  ('roadmap', 'roadmap', 7, 'published', 'A high-level plan showing the direction of a product over time.'),
  ('staging', 'staging', 7, 'published', 'A pre-production environment used for testing before release.'),
  ('production', 'production', 6, 'published', 'The live environment end users actually use.'),
  ('API', 'API', 8, 'published', 'Application Programming Interface — a contract for software components to communicate.'),
  ('database', 'database', 5, 'published', 'An organized collection of stored data.'),
  ('framework', 'framework', 6, 'published', 'A reusable software structure that provides generic functionality.'),
  ('frontend', 'frontend', 7, 'published', 'The user-facing part of an application.'),
  ('backend', 'backend', 7, 'published', 'The server-side part of an application.'),
  ('full-stack', 'full-stack', 6, 'published', 'Covering both frontend and backend development.'),
  ('DevOps', 'DevOps', 6, 'published', 'Practices combining software development and IT operations.'),
  ('CI/CD', 'CI/CD', 6, 'published', 'Continuous Integration / Continuous Deployment.'),
  ('pull request', 'pull request', 6, 'published', 'A request to merge one code branch into another, with review.'),
  ('merge', 'merge', 5, 'published', 'To combine changes from one code branch into another.'),
  ('commit', 'commit', 5, 'published', 'A saved snapshot of code changes in version control.'),
  ('branch', 'branch', 5, 'published', 'An independent line of code development in version control.'),
  ('bug', 'bug', 6, 'published', 'A defect or error in software.'),
  ('feature', 'feature', 6, 'published', 'A distinct piece of functionality in a product.'),
  ('release', 'release', 6, 'published', 'A published version of software made available to users.'),
  ('marketing plan', 'marketing plan', 7, 'published', 'A document outlining marketing strategy and goals.'),
  ('KPI', 'KPI', 7, 'published', 'Key Performance Indicator — a measurable value showing progress toward a goal.'),
  ('ROI', 'ROI', 7, 'published', 'Return on Investment.'),
  ('stakeholder', 'stakeholder', 6, 'published', 'A person or group with an interest in a project''s outcome.'),
  ('deadline', 'deadline', 6, 'published', 'The time by which something must be completed.'),
  ('milestone', 'milestone', 6, 'published', 'A significant point or event in a project timeline.'),
  ('workflow', 'workflow', 5, 'published', 'A sequence of steps to complete a task or process.'),
  ('onboarding', 'onboarding', 6, 'published', 'The process of integrating a new employee or user.'),
  ('offboarding', 'offboarding', 5, 'published', 'The process of formally separating an employee or user from an organization.'),
  ('dashboard', 'dashboard', 6, 'published', 'A visual display of key data and metrics.'),
  ('report', 'report', 4, 'published', 'A structured document summarizing information or data.'),
  ('feedback', 'feedback', 5, 'published', 'Information or opinions given in response to something.'),
  ('brainstorm', 'brainstorm', 5, 'published', 'A group discussion to generate ideas.'),
  ('mockup', 'mockup', 6, 'published', 'A static visual representation of a design.'),
  ('prototype', 'prototype', 6, 'published', 'An early working sample of a product used to test a concept.'),
  ('wireframe', 'wireframe', 6, 'published', 'A basic visual guide for a screen''s layout and structure.'),
  ('UX', 'UX', 7, 'published', 'User Experience.'),
  ('UI', 'UI', 7, 'published', 'User Interface.'),
  ('scope', 'scope', 5, 'published', 'The defined boundaries of a project''s work.'),
  ('timeline', 'timeline', 5, 'published', 'A schedule of events or tasks over time.'),
  ('budget', 'budget', 5, 'published', 'A financial plan for a project or organization.'),
  ('outsourcing', 'outsourcing', 5, 'published', 'Contracting work out to an external party.'),
  ('benchmark', 'benchmark', 5, 'published', 'A standard or reference point used for comparison.'),
  ('checklist', 'checklist', 4, 'published', 'A list of items to verify or complete.')
ON CONFLICT DO NOTHING;
