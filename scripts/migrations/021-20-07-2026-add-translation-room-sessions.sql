-- Migration: 021-20-07-2026-add-translation-room-sessions
-- Description:
--   Adds translation_room.translation_room_sessions: a TranslationRoom can be split into
--   multiple time-bounded sessions (main_language, audio_url, status, started_at/ended_at).
--   Also adds a nullable transcript.transcripts.translation_room_session_id logical FK so the
--   link is describable end-to-end, matching the existing translation_room_id "no physical FK"
--   convention already used on the same table.
--
--   SCOPE NOTE: this migration does NOT change the STT ingestion pipeline (stt_worker, Redis
--   stream keys stt:results:{roomId}, TranscriptRedisConsumerService.ProcessSttMessageAsync's
--   room-id-keyed lookup) to actually create/select a session per meeting. Nothing populates
--   translation_room_session_id yet — that is a follow-up pipeline change, tracked separately.

BEGIN;

CREATE TABLE IF NOT EXISTS translation_room.translation_room_sessions (
    id uuid NOT NULL DEFAULT (uuidv7()),
    translation_room_id uuid NOT NULL,
    main_language character varying(15) NOT NULL,
    audio_url character varying(500),
    status character varying(20) NOT NULL DEFAULT 'ACTIVE',
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT translation_room_sessions_pkey PRIMARY KEY (id),
    CONSTRAINT translation_room_sessions_translation_room_id_fkey FOREIGN KEY (translation_room_id) REFERENCES translation_room.translation_rooms(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS translation_room_sessions_translation_room_id_status_idx
    ON translation_room.translation_room_sessions (translation_room_id, status);

ALTER TABLE transcript.transcripts
    ADD COLUMN IF NOT EXISTS translation_room_session_id UUID;

COMMENT ON COLUMN transcript.transcripts.translation_room_session_id IS 'External TranslationRoomService session id (translation_room.translation_room_sessions). No physical FK. Not yet populated by any writer — see migration 021 header.';

COMMIT;
