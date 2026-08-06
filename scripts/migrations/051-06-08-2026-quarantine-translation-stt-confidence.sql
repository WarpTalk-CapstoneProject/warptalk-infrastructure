-- Migration: 051-06-08-2026-quarantine-translation-stt-confidence
-- Ticket: WT-277, WT-278
-- Created At: 2026-08-06
-- Description:
--   EXPAND HALF of an expand/contract pair. Adds transcript.translation_contents.source_stt_confidence
--   and backfills it. It does NOT rename and does NOT drop transcript.translation_contents.confidence.
--   The contract half — the DROP COLUMN — is written but deliberately NOT collectable by the
--   migrator; see "THE CONTRACT HALF" below.
--
--   WHY THIS IS SPLIT. scripts/deploy-release.sh runs `compose run --rm migrator` BEFORE
--   `compose up -d`, so every release applies every new migration in scripts/migrations/ ahead of
--   the service containers — including releases that change nothing about TranscriptService. The
--   first draft of this migration renamed confidence -> source_stt_confidence in one step. Merging
--   that meant the next release of ANYTHING would have renamed the column out from under the
--   running TranscriptService (backend 36224d3671f594e07de6cf145e8e7b817bb4ea47, which still reads
--   and writes `confidence`), turning every transcript translation read into a 42703. This file is
--   now safe to apply against that deployed backend with zero coordination: it only adds.
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
--     heard. The translator (OpenAITranslator) emits no score of its own. The number is therefore
--     moved to a column named for what it actually is — quarantined rather than deleted, because a
--     capstone defence is days away and the value still has diagnostic use.
--
--   ── COEXISTENCE: BOTH COLUMNS ARE LIVE, AND NEITHER IS COMPLETE ───────────────────────────────
--   Between this migration and the deploy of the TranscriptService build from backend PR #106,
--   two writers exist and they write different columns:
--     * deployed backend 36224d36…  writes `confidence`,             leaves source_stt_confidence NULL
--     * backend #106 once deployed   writes `source_stt_confidence`,  leaves confidence NULL
--   So for the length of that window, whichever column you read has a NULL hole in it. There is NO
--   trigger, NO generated column and NO sync job to close that hole. That is a decision, not an
--   oversight:
--     1. Nothing reads this value for correctness. It reaches exactly two surfaces —
--        TranscriptQueryService.GetTranslationsAsync -> TranscriptTranslationDto.Confidence, and
--        TranscriptGrpcService's GetTranscriptTranslations -> the transcript.proto confidence field.
--        Both types are already optional/nullable, and warptalk-web never binds the translation
--        confidence at all (src/types/transcript.ts declares it `confidence?: number` and no
--        component reads it; the only confidence the UI touches is the realtime SEGMENT confidence
--        in src/lib/transcript-display.ts, a different column this migration does not move).
--        Nothing in this repository reads it either: no observability query YAML, no rendered
--        Grafana/Prometheus config, no billing or cost script references translation_contents at
--        all.
--     2. A sync trigger would have to fire on both columns in both directions and would then have
--        to be dropped again by the contract migration — more moving parts, on the write path of
--        the hottest table in the transcript schema, to preserve a field nobody reads.
--     3. The hole is small and self-describing: a NULL here already means "unknown", which is
--        exactly the meaning WT-277 established. A row written by the other version is
--        indistinguishable from a row whose producer reported no logprobs, and both are honest.
--   If a real consumer of translation confidence ever appears, it must read
--   COALESCE(source_stt_confidence, confidence) until the contract migration lands, and treat the
--   result as a property of the AUDIO, never of the translation.
--
--   ── ASSUMPTION ABOUT EXISTING ROWS ────────────────────────────────────────────────────────────
--   The backfill copies values across as-is. It does NOT reinterpret them.
--   Because the old writer coalesced unknown to 1.0000, a stored 1.0000 is ambiguous: it may be a
--   real maximum-confidence measurement or a fabricated default. There is no evidence left in the
--   row to tell them apart, and no backup of the original message. Deleting every 1.0000 would
--   destroy genuine measurements; keeping them and treating them as trustworthy would keep
--   asserting something we cannot support. We keep them, unchanged, and record here that any row
--   created before this migration whose value is exactly 1.0000 must be treated as UNRELIABLE and
--   excluded from any confidence analysis. Only rows written after the WT-277 backend deploy carry
--   the NULL-means-unknown guarantee. (Additionally: STT confidence is an avg_logprob, which is
--   always <= 0, so a 1.0000 in transcript_segments.confidence is on its face not a real
--   measurement.)
--
--   ── THE CONTRACT HALF ─────────────────────────────────────────────────────────────────────────
--   scripts/migrations/pending/052-06-08-2026-drop-translation-contents-confidence.sql holds the
--   DROP COLUMN. It sits in pending/ because scripts/run-migrations.sh globs
--   "$MIGRATIONS_DIR"/*.sql non-recursively — a subdirectory is invisible to it, so the file ships
--   with the release image (deploy/k3s/migrator.Dockerfile does `COPY scripts /scripts`) without
--   ever running itself. There is no per-migration skip/gate flag in this repo; a directory the
--   collector does not descend into is the only mechanism available.
--   PRECONDITION for moving it up into scripts/migrations/: the release whose backend ref includes
--   WT-277/WT-278 (warptalk-backend PR #106, merged to development, NOT deployed as of 2026-08-06)
--   must already be running in production. Until then `confidence` stays.
--
--   NOT RUN as part of this change. Apply through the normal migration path.

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- 1. WT-278 — add the correctly named column, alongside the old one
-- ─────────────────────────────────────────────────────────────
-- DECIMAL(5,4), matching transcript.translation_contents.confidence as declared in
-- 017-15-07-2026-translation-cluster-finalize.sql. Nullable, and it stays nullable: NULL is the
-- WT-277 representation of "the producer reported no confidence", so a NOT NULL here would
-- reintroduce the exact defect this pair of tickets removes.
ALTER TABLE transcript.translation_contents
    ADD COLUMN IF NOT EXISTS source_stt_confidence DECIMAL(5,4);

-- One-time backfill for rows written before this migration. Guarded on the old column still
-- existing so this file remains re-runnable after the contract migration has dropped it.
-- The WHERE clause makes the copy idempotent and stops a re-run from overwriting a NULL that the
-- WT-277 backend deliberately wrote.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'transcript'
          AND table_name = 'translation_contents'
          AND column_name = 'confidence'
    ) THEN
        EXECUTE '
            UPDATE transcript.translation_contents
               SET source_stt_confidence = confidence
             WHERE source_stt_confidence IS NULL
               AND confidence IS NOT NULL';

        EXECUTE $c$
            COMMENT ON COLUMN transcript.translation_contents.confidence IS
                'DEPRECATED (WT-278), retained only for the expand/contract window opened by '
                'migration 051. Same value as source_stt_confidence and equally mislabelled: it is '
                'the SOURCE segment STT avg_logprob, never a translation quality score. Written '
                'only by TranscriptService builds older than WT-277/WT-278. Do not read it, do not '
                'add new writers. Dropped by pending/052 once the WT-277 backend is deployed.'
        $c$;
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 2. WT-277 — NULL must remain expressible on every confidence column
-- ─────────────────────────────────────────────────────────────
-- All three are already nullable, so these are no-ops today. They are here so that a future
-- migration adding NOT NULL has to consciously undo an explicit statement, and they are safe
-- against the deployed backend: relaxing a constraint cannot break a writer.
ALTER TABLE transcript.transcript_segments
    ALTER COLUMN confidence DROP NOT NULL;

ALTER TABLE transcript.translation_contents
    ALTER COLUMN source_stt_confidence DROP NOT NULL;

-- Same pin for the deprecated column, guarded so this file still re-runs after pending/052 has
-- dropped it.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'transcript'
          AND table_name = 'translation_contents'
          AND column_name = 'confidence'
    ) THEN
        EXECUTE 'ALTER TABLE transcript.translation_contents
                     ALTER COLUMN confidence DROP NOT NULL';
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 3. Say in the schema what these columns are
-- ─────────────────────────────────────────────────────────────
COMMENT ON COLUMN transcript.transcript_segments.confidence IS
    'STT model confidence for this segment (an avg_logprob, so <= 0). NULL = the producer reported '
    'no confidence (no token logprobs on the event, an unparsable field, or the -1.0 sentinel) — '
    'WT-277: never coalesce this to a number on write. Rows written before the WT-277 backend '
    'deploy whose value is exactly 1.0000 are unreliable: the old writer used 1.0 as its '
    'missing-value default.';

COMMENT ON COLUMN transcript.translation_contents.source_stt_confidence IS
    'WT-278: the STT confidence of the SOURCE segment this translation was derived from — a '
    'measurement of the audio, NOT of the translation. Supersedes the "confidence" column, which '
    'migration 051 keeps alive only until the contract migration. The translator produces no '
    'quality score; do not surface this as translation quality in any API, export or UI. NULL = '
    'the source segment carried no usable confidence, OR the row was written by a pre-WT-277 '
    'backend that only knew the old column. A real translation quality signal (back-translation, '
    'COMET-style scoring) must get its own new column, not reuse this one.';

COMMIT;
