-- Migration: 053-07-08-2026-add-translation-room-reminder-30min
-- Ticket: WT-326
-- Created At: 2026-08-07
-- Description:
--   Adds the sent-state column for the third meeting reminder window, T-30min, alongside the
--   T-10min and T-1min columns 035-24-07-2026-add-translation-room-reminder-tracking.sql added
--   for WT-14. ReminderNotificationWorker stamps it right after the reminder is sent, so a
--   restart or a slow poll never double-sends for the same window.
--
--   WHICH FILE MATTERS. This one changes nothing any running service reads.
--   scripts/service-migrations/translation-room/20260807090000_add_translation_room_reminder_30min.sql
--   is the one that reaches warptalk_translation_room, the database TranslationRoomService is
--   actually connected to; its source lives in warptalk-backend/translation-room/database/migrations/
--   and it was staged here by collect-service-migrations.sh, exactly as WT-294 requires.
--   scripts/migrations/ is applied to the legacy monolith database `warptalk`, which no service has
--   connected to since the extraction. This file exists so that schema stays a truthful reference
--   (008-...-full-schema.dbml and the ERDs derive from it) and so check-service-migration-coverage.sh's
--   mirroring rule is satisfied by a real counterpart rather than a LEGACY-ONLY.txt entry. It follows
--   the 049/050/051/052 precedent. THE TWO FILES CARRY IDENTICAL STATEMENTS; EDIT BOTH OR NEITHER.
--
--   NUMBERING. 052 is taken by warptalk-infrastructure#69 / warptalk-backend#119 (WT-327 daily
--   recurring meetings), still open at the time of writing, and by
--   scripts/migrations/pending/052-06-08-2026-drop-translation-contents-confidence.sql. This file
--   takes 053 so neither has to be renumbered.
--
--   ONE COLUMN PER WINDOW is the shape WT-14 established and this deliberately follows it rather
--   than generalising two columns into a windows table: three windows do not pay for the join, and
--   the sweep predicate reads all three in one indexed scan of translation_rooms.
--
--   ADDITIVE ONLY, and safe to apply ahead of the service containers the way deploy-release.sh
--   does: the column is nullable with no default, so existing rows read as "not yet reminded for
--   T-30min", which is exactly true, and a backend that predates WT-326 never selects it.

ALTER TABLE translation_room.translation_rooms
    ADD COLUMN IF NOT EXISTS reminder_30min_sent_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN translation_room.translation_rooms.reminder_30min_sent_at IS
    'WT-326. Set once the T-30min reminder notification has been sent for this room; NULL means it has not.';
