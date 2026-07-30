-- Chat translations are cached by (message_id, target_language). Without a version
-- marker, changing the translation prompt/model later has no way to invalidate stale
-- cached rows — old translations would keep being served forever. Add prompt_version
-- and fold it into the cache key: bumping it in code makes old rows a cache miss
-- (retranslated with the new prompt) without deleting the historical rows.
ALTER TABLE meeting.meeting_chat_translations
    ADD COLUMN IF NOT EXISTS prompt_version INTEGER NOT NULL DEFAULT 1;

DROP INDEX IF EXISTS meeting.ix_meeting_chat_translations_message_target;

CREATE UNIQUE INDEX IF NOT EXISTS ix_meeting_chat_translations_message_target_version
    ON meeting.meeting_chat_translations (message_id, target_language, prompt_version);
