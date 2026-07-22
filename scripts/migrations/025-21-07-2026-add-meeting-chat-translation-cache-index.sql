-- Meeting chat translations are looked up by (message_id, target_language) as a cache
-- key before calling the LLM. meeting_chat_translations only had its PK index, so every
-- lookup and the eventual concurrent-click race relied on a full scan / had no uniqueness
-- guarantee. Add the index the cache lookup actually needs.
CREATE UNIQUE INDEX IF NOT EXISTS ix_meeting_chat_translations_message_target
    ON meeting.meeting_chat_translations (message_id, target_language);
