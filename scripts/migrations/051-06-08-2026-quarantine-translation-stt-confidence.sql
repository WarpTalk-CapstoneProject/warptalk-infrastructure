-- Migration: 051-06-08-2026-quarantine-translation-stt-confidence
-- Ticket: WT-277, WT-278
-- Created At: 2026-08-06
-- Description:
--   Makes "we do not know the confidence" storable and stops a translation row from carrying a
--   number that does not describe the translation.
--
--   WT-277 — a missing confidence was stored as 1.0000.
--     TranscriptRedisConsumerService read confidence as
--       float.TryParse(values["confidence"], out var conf) ? conf : 1.0f
--     so a message with no confidence field, an unparsable one, or warptalk-ai's explicit -1.0
--     "this realtime event exposed no token logprobs" sentinel
--     (warptalk-ai/stt_worker/model.py: float(seg.get("avg_logprob", -1.0))) all persisted as
--     1.0000 — the MAXIMUM. "Unknown" became byte-identical to "perfect".
--     Both columns were already declared nullable, so this migration adds no DDL for that; the
--     defect was entirely in the writer, which now writes NULL. The DROP NOT NULL statements below
--     are defensive no-ops that pin the intent so a later change cannot quietly re-require a value,
--     and the COMMENTs state what NULL means.
--
--   WT-278 — transcript.translation_contents.confidence never measured the translation.
--     warptalk-ai/translation_worker/worker.py set the published confidence to
--     stt_result.confidence: the SOURCE segment's avg_logprob, i.e. how clearly the AUDIO was
--     heard. The translator (OpenAITranslator) emits no score of its own. The column is therefore
--     renamed to source_stt_confidence — quarantined rather than dropped, because a capstone
--     defence is days away and a rename keeps whatever diagnostic value the number has while
--     removing every path by which it can be read as translation quality.
--
--   ── ASSUMPTION ABOUT EXISTING ROWS ────────────────────────────────────────────────────────────
--   Existing data is NOT rewritten and NOT reinterpreted.
--   Because the old writer coalesced unknown to 1.0000, a stored 1.0000 is now ambiguous: it may
--   be a real maximum-confidence measurement or a fabricated default. There is no evidence left in
--   the row to tell them apart, and no backup of the original message. Deleting every 1.0000
--   would destroy genuine measurements; keeping them and treating them as trustworthy would keep
--   asserting something we cannot support. We keep them, unchanged, and record here that any row
--   created before this migration whose value is exactly 1.0000 must be treated as UNRELIABLE and
--   excluded from any confidence analysis. Only rows written after this migration carry the
--   NULL-means-unknown guarantee. (Additionally: STT confidence is an avg_logprob, which is always
--   <= 0, so a 1.0000 in transcript_segments.confidence is on its face not a real measurement.)
--
--   NOT RUN as part of this change. Apply through the normal migration path. The rename must land
--   BEFORE the TranscriptService build that maps TranslationContent.SourceSttConfidence is
--   deployed, because EF will SELECT source_stt_confidence.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 1. WT-278 — rename the mislabelled translation column
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'transcript'
          AND table_name = 'translation_contents'
          AND column_name = 'confidence'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'transcript'
          AND table_name = 'translation_contents'
          AND column_name = 'source_stt_confidence'
    ) THEN
        ALTER TABLE transcript.translation_contents
            RENAME COLUMN confidence TO source_stt_confidence;
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 2. WT-277 — NULL must remain expressible on both columns
-- ─────────────────────────────────────────────────────────────
ALTER TABLE transcript.transcript_segments
    ALTER COLUMN confidence DROP NOT NULL;

ALTER TABLE transcript.translation_contents
    ALTER COLUMN source_stt_confidence DROP NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- 3. Say in the schema what these columns are
-- ─────────────────────────────────────────────────────────────
COMMENT ON COLUMN transcript.transcript_segments.confidence IS
    'STT model confidence for this segment (an avg_logprob, so <= 0). NULL = the producer reported '
    'no confidence (no token logprobs on the event, an unparsable field, or the -1.0 sentinel) — '
    'WT-277: never coalesce this to a number on write. Rows written before migration 051 whose '
    'value is exactly 1.0000 are unreliable: the old writer used 1.0 as its missing-value default.';

COMMENT ON COLUMN transcript.translation_contents.source_stt_confidence IS
    'WT-278: the STT confidence of the SOURCE segment this translation was derived from — a '
    'measurement of the audio, NOT of the translation. Renamed from "confidence". The translator '
    'produces no quality score; do not surface this as translation quality in any API, export or '
    'UI. NULL = the source segment carried no usable confidence. A real translation quality signal '
    '(back-translation, COMET-style scoring) must get its own new column, not reuse this one.';

COMMIT;
