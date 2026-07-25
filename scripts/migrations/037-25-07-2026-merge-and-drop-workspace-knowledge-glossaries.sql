-- Migration: Retire the orphan workspace.workspace_knowledge_glossaries table.
-- Created At: 2026-07-25
--
-- Context (docs/global-glossary-plan.md §1.2/§2.2/§9): this table was created in migration
-- 008-03-06-2026-add-workspace-documents-and-glossary.sql, EF-mapped, and then never wired to
-- any service/controller — transcript.glossaries/glossary_terms (GlossaryService,
-- GlossariesController) is the glossary model that actually runs, feeds STT/MT prompts, and
-- now merges with transcript.global_glossary_terms. Two parallel, incompatible glossary shapes
-- is worse than one — this migration keeps the field, drops the table.
--
-- definition/usage_note/part_of_speech are genuinely useful (RAG context, admin-facing term
-- explanations) so they're carried over onto transcript.glossary_terms rather than lost.
-- workspace_knowledge_glossaries had no rows reachable through any API, so there is no data to
-- backfill — this is a schema-only migration.

ALTER TABLE transcript.glossary_terms
  ADD COLUMN IF NOT EXISTS definition TEXT,
  ADD COLUMN IF NOT EXISTS usage_note TEXT,
  ADD COLUMN IF NOT EXISTS part_of_speech VARCHAR(50);

DROP TABLE IF EXISTS workspace.workspace_knowledge_glossaries;
