-- Migration: 017-15-07-2026-translation-cluster-finalize
-- Description:
--   Finalizes the translation_room / transcript / meeting / subscription schema cluster to
--   match the v4 target design (diagrams/R2-erd/warptalk-v4-final.dbml, 3 review rounds)
--   after verifying the actual current schema (init-db.sql + migrations 000-016) against it.
--
--   Column types follow the project's own established convention: migrations 011 and 014
--   already converted every status/type enum in meeting/translation_room/transcript to
--   VARCHAR. This migration does NOT reintroduce native Postgres ENUM types, even though
--   the dbml source still lists them as `Enum ...` — that part of the dbml is stale and
--   should be corrected (see companion warptalk-final-translation-cluster.dbml).
--
--   Every "logical FK" (cross-service reference) is intentionally left WITHOUT a physical
--   FOREIGN KEY constraint, consistent with every other cross-schema reference already in
--   this codebase (e.g. translation_rooms.workspace_id, translation_rooms.host_id).
--
--   Schema naming: the billing schema is called `subscription` in this codebase and stays
--   that way — "billing" is only the informal/spoken name for it, not the schema name.
--   No RENAME SCHEMA is performed by this migration.
--
-- Migration 016 now creates the active-subscription index against the canonical
-- `subscription.subscriptions.is_active` model. Step 0 intentionally repeats the
-- idempotent definition so databases created from older migration bundles converge.

BEGIN;

-- ============================================================================
-- STEP 0 — Converge the active-subscription uniqueness index.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_one_active_per_workspace_idx
    ON subscription.subscriptions (workspace_id)
    WHERE is_active = true AND workspace_id IS NOT NULL;

-- ============================================================================
-- STEP 1 — transcript.transcripts: head-pointer + STT audit trail
-- Why: today the "current" transcript for a room is found via MAX(version), which races
-- under concurrent writers. is_current makes it an explicit, indexable invariant.
-- ============================================================================

ALTER TABLE transcript.transcripts
  ADD COLUMN IF NOT EXISTS is_current BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS previous_transcript_id UUID,
  ADD COLUMN IF NOT EXISTS engine_version VARCHAR(50),
  ADD COLUMN IF NOT EXISTS last_sequence_order INT NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'transcripts_previous_transcript_id_fkey'
    ) THEN
        ALTER TABLE transcript.transcripts
          ADD CONSTRAINT transcripts_previous_transcript_id_fkey
          FOREIGN KEY (previous_transcript_id) REFERENCES transcript.transcripts (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS transcripts_one_current_per_room_idx
  ON transcript.transcripts (translation_room_id)
  WHERE is_current;

-- last_sequence_order MUST be advanced via:
--   UPDATE transcript.transcripts SET last_sequence_order = last_sequence_order + 1
--   WHERE id = :id RETURNING last_sequence_order;
-- in the SAME transaction as the segment insert. Read-MAX-then-insert at the app layer
-- races under concurrent segment writers — do not reintroduce that pattern.

-- ============================================================================
-- STEP 2 — transcript.transcript_segments: draft/final + cross-version matching
-- Why: billing (STT/TRANSLATION/AUDIO_DUBBING charges) must only fire once a segment is
-- final, never on STT interim drafts that are about to be overwritten.
-- ============================================================================

ALTER TABLE transcript.transcript_segments
  ADD COLUMN IF NOT EXISTS is_final BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS matched_segment_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'transcript_segments_matched_segment_id_fkey'
    ) THEN
        ALTER TABLE transcript.transcript_segments
          ADD CONSTRAINT transcript_segments_matched_segment_id_fkey
          FOREIGN KEY (matched_segment_id) REFERENCES transcript.transcript_segments (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

-- Existing rows are historical/committed data -> default true is correct for backfill.
-- New STT writes must explicitly pass is_final = false for interim/streaming segments.

-- ============================================================================
-- STEP 3 — transcript.translation_contents + segment_translation_links
-- Replaces the 1:1 transcript_translations design. transcript_translations is KEPT for
-- this release (dual-write/read) and dropped in a follow-up migration once
-- TranscriptService and translation_worker have cut over.
-- ============================================================================

CREATE TABLE IF NOT EXISTS transcript.translation_contents (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,                      -- logical FK -> workspace.workspaces, no physical FK
  text_hash VARCHAR(64) NOT NULL,
  target_language VARCHAR(15) NOT NULL,
  translated_text TEXT NOT NULL,
  translator_model VARCHAR(100) NOT NULL,
  confidence DECIMAL(5,4),
  is_retranslated BOOLEAN NOT NULL DEFAULT false,
  previous_translation_content_id UUID,
  latency_ms INT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',    -- pending|processing|done|failed (claim-state)
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'translation_contents_previous_content_id_fkey'
    ) THEN
        ALTER TABLE transcript.translation_contents
          ADD CONSTRAINT translation_contents_previous_content_id_fkey
          FOREIGN KEY (previous_translation_content_id) REFERENCES transcript.translation_contents (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

-- This unique index IS the atomic claim mechanism: workers INSERT ... ON CONFLICT
-- (workspace_id, text_hash, target_language) DO NOTHING RETURNING id. Winner processes,
-- losers poll the winning row until status = 'done'. Scoped by workspace_id so two
-- tenants saying the same sentence never share (and never leak) a translation.
CREATE UNIQUE INDEX IF NOT EXISTS translation_contents_dedup_idx
  ON transcript.translation_contents (workspace_id, text_hash, target_language);

CREATE TABLE IF NOT EXISTS transcript.segment_translation_links (
  segment_id UUID NOT NULL,
  translation_content_id UUID NOT NULL,
  target_language VARCHAR(15) NOT NULL,             -- denormalized from translation_contents at insert time
  is_current BOOLEAN NOT NULL DEFAULT true,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  PRIMARY KEY (segment_id, translation_content_id)
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'segment_translation_links_segment_id_fkey') THEN
        ALTER TABLE transcript.segment_translation_links
          ADD CONSTRAINT segment_translation_links_segment_id_fkey
          FOREIGN KEY (segment_id) REFERENCES transcript.transcript_segments (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'segment_translation_links_content_id_fkey') THEN
        ALTER TABLE transcript.segment_translation_links
          ADD CONSTRAINT segment_translation_links_content_id_fkey
          FOREIGN KEY (translation_content_id) REFERENCES transcript.translation_contents (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS segment_translation_links_current_unique_idx
  ON transcript.segment_translation_links (segment_id, target_language)
  WHERE is_current;

-- Backfill from the legacy 1:1 table into the dedup model.
INSERT INTO transcript.translation_contents
  (workspace_id, text_hash, target_language, translated_text, translator_model, confidence,
   is_retranslated, latency_ms, status, created_at, updated_at)
SELECT DISTINCT ON (t.workspace_id, md5(tt.translated_text), tt.target_language)
  t.workspace_id, md5(tt.translated_text), tt.target_language, tt.translated_text,
  tt.translator_model, tt.confidence, tt.is_retranslated, tt.latency_ms, 'done',
  tt.created_at, tt.updated_at
FROM transcript.transcript_translations tt
JOIN transcript.transcript_segments ts ON ts.id = tt.segment_id
JOIN transcript.transcripts t ON t.id = ts.transcript_id
ON CONFLICT DO NOTHING;

INSERT INTO transcript.segment_translation_links (segment_id, translation_content_id, target_language, is_current, created_at)
SELECT tt.segment_id, tc.id, tt.target_language, true, tt.created_at
FROM transcript.transcript_translations tt
JOIN transcript.transcript_segments ts ON ts.id = tt.segment_id
JOIN transcript.transcripts t ON t.id = ts.transcript_id
JOIN transcript.translation_contents tc
  ON tc.workspace_id = t.workspace_id
 AND tc.text_hash = md5(tt.translated_text)
 AND tc.target_language = tt.target_language
ON CONFLICT DO NOTHING;

-- ============================================================================
-- STEP 4 — transcript.audio_dubbings (new entity)
--
-- Originally designed with a voice_profile_id FK to a new transcript.voice_profiles
-- table (persistent, consent-tracked, SYSTEM/USER owned). Dropped after tracing the
-- real tts_worker pipeline (warptalk-ai/tts_worker/worker.py): voice cloning there is
-- ephemeral and provider-driven — Cartesia mints a voice_id per speaker per room,
-- cached only in Redis (`voice:{translation_room_id}:{speaker_id}`, TTL-bound), never
-- persisted anywhere. Nothing in the codebase would ever have written a row into that
-- table, so it would have shipped as dead schema — see the "no lying schema" reasoning
-- in the accompanying design discussion. voice.voice_profiles (separate live schema)
-- is untouched by this migration for the same reason: it already has zero writers.
--
-- Instead, audio_dubbings carries the fields tts_worker's TTSResultMessage already
-- produces natively (voice_type, clone_provider, provider_voice_id — the last of
-- these added to TTSResultMessage alongside this migration so the pipeline actually
-- has a producer for every column here, not just a schema that hopes for one).
-- ============================================================================

CREATE TABLE IF NOT EXISTS transcript.audio_dubbings (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  workspace_id UUID NOT NULL,
  translation_content_id UUID NOT NULL,
  text_hash VARCHAR(64) NOT NULL,
  voice_type VARCHAR(20) NOT NULL,                    -- 'cloned' | 'default' — matches TTSResultMessage.voice_type exactly
  provider VARCHAR(50) NOT NULL DEFAULT 'cartesia',   -- matches TTSResultMessage.clone_provider/anchor_provider
  provider_voice_id VARCHAR(255) NOT NULL,            -- raw Cartesia voice id actually used — always populated, even for voice_type='default'
  previous_audio_dubbing_id UUID,
  audio_url VARCHAR(500),
  duration_ms INT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',      -- claim-state, same pattern as translation_contents.status
  created_at TIMESTAMPTZ NOT NULL DEFAULT (NOW()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT (NOW())
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'audio_dubbings_translation_content_id_fkey') THEN
        ALTER TABLE transcript.audio_dubbings
          ADD CONSTRAINT audio_dubbings_translation_content_id_fkey
          FOREIGN KEY (translation_content_id) REFERENCES transcript.translation_contents (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'audio_dubbings_previous_dubbing_id_fkey') THEN
        ALTER TABLE transcript.audio_dubbings
          ADD CONSTRAINT audio_dubbings_previous_dubbing_id_fkey
          FOREIGN KEY (previous_audio_dubbing_id) REFERENCES transcript.audio_dubbings (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

-- provider_voice_id (not voice_type) is the correct dedup disambiguator: two different
-- speakers both using a "cloned" voice for the same sentence must NOT collapse into one
-- row (their voices sound different) — but they always resolve to different Cartesia
-- voice ids, so keying on that id (which is populated for the 'default' case too, via
-- CartesiaSynthesizer._default_voice_id) dedups correctly in both cases.
CREATE UNIQUE INDEX IF NOT EXISTS audio_dubbings_dedup_idx
  ON transcript.audio_dubbings (workspace_id, text_hash, provider_voice_id);
CREATE INDEX IF NOT EXISTS audio_dubbings_translation_idx ON transcript.audio_dubbings (translation_content_id);

-- NOTE: nothing writes to this table yet. Populating it requires
-- transcript.translation_contents to already have a row to point
-- translation_content_id at, which belongs in TranscriptService's own STT/translation
-- Redis consumer (matching how transcript_segments/transcript_translations already get
-- persisted there) — not in the Python billing_worker, which only settles credits (see
-- warptalk-ai/billing_worker/worker.py's module docstring for the same note).

-- ============================================================================
-- STEP 5 — transcript.transcript_corrections: billing reversal link
-- ============================================================================

ALTER TABLE transcript.transcript_corrections
  ADD COLUMN IF NOT EXISTS translation_content_id UUID,        -- only set when correction_type = TRANSLATION
  ADD COLUMN IF NOT EXISTS reversal_credit_transaction_id UUID; -- soft ref -> subscription.credit_transactions, no physical FK (cross-service)

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'transcript_corrections_translation_content_id_fkey') THEN
        ALTER TABLE transcript.transcript_corrections
          ADD CONSTRAINT transcript_corrections_translation_content_id_fkey
          FOREIGN KEY (translation_content_id) REFERENCES transcript.translation_contents (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS transcript_corrections_segment_idx ON transcript.transcript_corrections (segment_id);
CREATE INDEX IF NOT EXISTS transcript_corrections_status_idx ON transcript.transcript_corrections (status);
CREATE INDEX IF NOT EXISTS transcript_corrections_translation_content_idx ON transcript.transcript_corrections (translation_content_id);

-- ============================================================================
-- STEP 6 — translation_room.translation_room_audio_routes: head-pointer
-- Why (confirmed against TranslationRoomAudioRouteService.GenerateRoutesAsync, which
-- rebuilds a full source x target mesh on every call): today nothing stops two
-- "active" rows existing for the same (source, target) pair after a reconnect, which
-- would double up STT/TRANSLATION/AUDIO_DUBBING billing for the same speaker/listener pair.
-- ============================================================================

ALTER TABLE translation_room.translation_room_audio_routes
  ADD COLUMN IF NOT EXISTS is_current BOOLEAN NOT NULL DEFAULT true;

CREATE UNIQUE INDEX IF NOT EXISTS audio_routes_one_current_per_pair_idx
  ON translation_room.translation_room_audio_routes (source_participant_id, target_participant_id)
  WHERE is_current;

-- ============================================================================
-- STEP 7 — meeting.meeting_rooms: head-pointer
-- meeting_rooms.active_host_id already shipped in migration
-- 013-14-06-2026-add-meeting-active-host.sql. This step only adds is_current, which that
-- migration did not include.
-- ============================================================================

ALTER TABLE meeting.meeting_rooms
  ADD COLUMN IF NOT EXISTS is_current BOOLEAN NOT NULL DEFAULT true;

CREATE UNIQUE INDEX IF NOT EXISTS meeting_rooms_one_current_per_troom_idx
  ON meeting.meeting_rooms (translation_room_id)
  WHERE is_current;

-- ============================================================================
-- STEP 8 — meeting.meeting_participants: link back to the business participant
-- Required for STT to attribute transcript_segments.speaker_participant_id correctly,
-- especially for GUEST participants where user_id is NULL on both sides so no join by
-- user_id is possible.
-- ============================================================================

ALTER TABLE meeting.meeting_participants
  ADD COLUMN IF NOT EXISTS translation_room_participant_id UUID, -- logical FK -> translation_room.translation_room_participants.id
  ADD COLUMN IF NOT EXISTS device_info VARCHAR(255);

-- ============================================================================
-- STEP 9 — subscription.credit_transactions: extend existing table to the claim-state /
-- audit-trail design instead of creating a second, competing ledger table.
-- subscription.credit_transactions already has `reference_id` + `reference_type` doing a
-- similar job to the target design's polymorphic reference_id/charge_type pair — this
-- step ADDS the missing audit/idempotency columns without renaming what already works.
-- ============================================================================

CREATE TABLE IF NOT EXISTS subscription.usage_rate_card (
  id UUID PRIMARY KEY DEFAULT (uuidv7()),
  charge_type VARCHAR(30) NOT NULL,                 -- STT | TRANSLATION | AUDIO_DUBBING_STANDARD | AUDIO_DUBBING_VOICE_CLONE | AI_ASSISTANT | OTHER
  source_language_code VARCHAR(15),                 -- NULL = no source-language override
  target_language_code VARCHAR(15),                 -- NULL = no target-language override
  unit_price DECIMAL(12,6) NOT NULL,
  currency CHAR(3) NOT NULL,
  effective_from TIMESTAMPTZ NOT NULL,
  effective_to TIMESTAMPTZ                          -- NULL = currently active row (append-only pricing history)
);
CREATE INDEX IF NOT EXISTS usage_rate_card_lookup_idx
  ON subscription.usage_rate_card (charge_type, currency, source_language_code, target_language_code, effective_from);
CREATE UNIQUE INDEX IF NOT EXISTS usage_rate_card_one_active_per_combo_idx
  ON subscription.usage_rate_card (charge_type, currency, source_language_code, target_language_code)
  WHERE effective_to IS NULL;

ALTER TABLE subscription.credit_transactions
  ADD COLUMN IF NOT EXISTS charge_type VARCHAR(30),          -- discriminator; mirrors existing `type` column, additive (do not drop `type` — app code still reads it)
  ADD COLUMN IF NOT EXISTS pricing_rate_card_id UUID,
  ADD COLUMN IF NOT EXISTS usage_record_id UUID,
  ADD COLUMN IF NOT EXISTS unit_price_snapshot DECIMAL(12,6), -- copy of the price actually applied; rate_card FK is a live reference and must not be re-read for historical rows
  ADD COLUMN IF NOT EXISTS invoice_id UUID,
  ADD COLUMN IF NOT EXISTS reversal_of_transaction_id UUID,
  ADD COLUMN IF NOT EXISTS currency CHAR(3),
  ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(255),
  ADD COLUMN IF NOT EXISTS triggered_by_participant_id UUID;  -- logical FK -> translation_room.translation_room_participants.id, reporting only, workspace is always the payer

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'credit_transactions_pricing_rate_card_id_fkey') THEN
        ALTER TABLE subscription.credit_transactions
          ADD CONSTRAINT credit_transactions_pricing_rate_card_id_fkey
          FOREIGN KEY (pricing_rate_card_id) REFERENCES subscription.usage_rate_card (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'credit_transactions_usage_record_id_fkey') THEN
        ALTER TABLE subscription.credit_transactions
          ADD CONSTRAINT credit_transactions_usage_record_id_fkey
          FOREIGN KEY (usage_record_id) REFERENCES subscription.usage_records (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'credit_transactions_invoice_id_fkey') THEN
        ALTER TABLE subscription.credit_transactions
          ADD CONSTRAINT credit_transactions_invoice_id_fkey
          FOREIGN KEY (invoice_id) REFERENCES subscription.invoices (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'credit_transactions_reversal_of_transaction_id_fkey') THEN
        ALTER TABLE subscription.credit_transactions
          ADD CONSTRAINT credit_transactions_reversal_of_transaction_id_fkey
          FOREIGN KEY (reversal_of_transaction_id) REFERENCES subscription.credit_transactions (id)
          DEFERRABLE INITIALLY IMMEDIATE;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS credit_transactions_idempotency_key_idx
  ON subscription.credit_transactions (idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS credit_transactions_reversal_unique_idx
  ON subscription.credit_transactions (reversal_of_transaction_id)
  WHERE reversal_of_transaction_id IS NOT NULL;

-- usage_record_id -> subscription.usage_records and invoice_id -> subscription.invoices
-- both already exist; no new table required for either.

COMMIT;

-- ============================================================================
-- OUT OF SCOPE for this migration (tracked separately, not schema changes):
--
-- 1. Enforcing "a translation room must have >= 1 source participant and >= 1 target
--    participant before it can start" is a cross-row business invariant, not something a
--    CHECK/FK constraint can express. TranslationRoomService.StartTranslationRoomAsync
--    (WarpTalk.TranslationRoomService.Application/Services/TranslationRoomService.cs:380)
--    currently does NOT verify this — it only checks host authorization and room status.
--    Add the check there: require at least one row in
--    translation_room.translation_room_audio_routes (translation_room_id = :id, is_current)
--    before allowing SCHEDULED/WAITING -> IN_PROGRESS.
--
-- 2. meeting.meeting_participants row order is not guaranteed to put the host first —
--    MeetingRoomService.JoinMeetingAsync lets any authorized participant create the
--    MeetingRoom/MeetingParticipant row before the host joins (they're just held in a
--    waiting room without a real LiveKit token). If "participant #1 = host" must be a
--    hard data invariant rather than a UI-level effect, that also needs an app-layer
--    change, not a schema change.
--
-- 3. Dropping transcript.transcript_translations is deferred to a follow-up migration
--    once TranscriptService/translation_worker have cut over to translation_contents.
--
-- 4. transcript.audio_dubbings.translation_content_id is NOT NULL but nothing populates
--    it yet — see the note directly under that table's DDL above. Wiring TTS results
--    into it is real integration work (TranscriptService consumer), not a schema change.
--
-- 5. voice.voice_profiles / voice_consents / voice_samples (separate live schema) are
--    left as-is. They already have zero writers in the codebase; this migration doesn't
--    make that better or worse, just doesn't add a second unused voice-profile table
--    alongside them (an earlier draft of this migration did exactly that — see
--    warptalk-final-translation-cluster.dbml's changelog note on transcript.voice_profiles).
-- ============================================================================
