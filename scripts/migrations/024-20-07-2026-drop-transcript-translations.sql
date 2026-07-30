-- Migration: 024-20-07-2026-drop-transcript-translations
-- Description:
--   Drops transcript.transcript_translations (TD-003). Confirmed dead: the real-time
--   translation pipeline (TranscriptRedisConsumerService.ProcessTranslateMessageAsync)
--   writes to transcript.translation_contents / transcript.segment_translation_links
--   instead (deduplicated text + versioned segment links), and CodeGraph confirmed zero
--   remaining callers of the TranscriptTranslation entity/repository anywhere in the
--   codebase. GetTranslationsAsync (TranscriptQueryService) has been repointed to read
--   from translation_contents/segment_translation_links, so this table is safe to drop.

BEGIN;

DROP TABLE IF EXISTS transcript.transcript_translations;

COMMIT;
