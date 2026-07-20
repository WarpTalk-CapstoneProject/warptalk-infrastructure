-- Migration: 022-20-07-2026-add-transcript-segment-id-to-billing
-- Description:
--   Adds a stable, non-polymorphic transcript_segment_id reference to billing so
--   credit_transactions/usage_records can always be traced back to the real
--   transcript.transcript_segments.id that caused the charge, regardless of charge_type
--   (STT/TRANSLATION/AUDIO_DUBBING_*). This is additive alongside credit_transactions'
--   existing reference_id/reference_type polymorphic pair (reference_type is
--   "translation_content"/"audio_dubbing" for those charge types, not "transcript_segment" —
--   so reference_id alone does not consistently resolve to a segment id today).
--
--   NOTE ON usage_records: subscription.usage_records already got a `segment_id UUID` column
--   from migration 016-16-07-2026-add-segment-id-to-usage-records.sql, which was unpopulated
--   AND missing from this README's documented apply order (fixed in this same change — see
--   README edit). This migration does NOT add a second, differently-named column to
--   usage_records — it only adds the missing index and lets billing_worker start populating
--   the column that already exists. credit_transactions has no equivalent column today, so
--   transcript_segment_id is added there fresh.
--
--   No physical FK on either column: transcript lives in a different schema/service, same
--   convention as credit_transactions.triggered_by_participant_id (migration 017).

BEGIN;

CREATE INDEX IF NOT EXISTS usage_records_segment_id_idx
    ON subscription.usage_records (segment_id)
    WHERE segment_id IS NOT NULL;

ALTER TABLE subscription.credit_transactions
    ADD COLUMN IF NOT EXISTS transcript_segment_id UUID;

COMMENT ON COLUMN subscription.credit_transactions.transcript_segment_id IS 'External TranscriptService transcript_segments.id. No physical FK.';

CREATE INDEX IF NOT EXISTS credit_transactions_transcript_segment_id_idx
    ON subscription.credit_transactions (transcript_segment_id)
    WHERE transcript_segment_id IS NOT NULL;

COMMIT;
