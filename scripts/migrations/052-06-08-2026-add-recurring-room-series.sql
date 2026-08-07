-- Migration: 052-06-08-2026-add-recurring-room-series
-- Ticket: WT-327
-- Created At: 2026-08-06
-- Description:
--   Recurring meeting bookings ("Daily at 08:00").
--
--   THIS FILE CHANGES NOTHING ANY RUNNING SERVICE READS. scripts/migrations/ is applied by
--   run-migrations.sh to the LEGACY MONOLITH database `warptalk`, which no service has connected
--   to since the logical-database extraction. The migration TranslationRoomService actually needs
--   is its own, staged at
--     scripts/service-migrations/translation-room/20260806120000_add_recurring_room_series.sql
--   (source: warptalk-backend/translation-room/database/migrations/). This file exists only so the
--   legacy schema — which 008-18-05-2026-full-schema.sql and the ERDs derive from — stays a
--   truthful reference, and so check-service-migration-coverage.sh's mirroring rule is satisfied
--   by a real counterpart rather than a LEGACY-ONLY.txt entry.
--
--   The two files are byte-for-byte the same statements. If you are editing one, edit both.
--
--   SHAPE, AND WHY
--     A series row is a BOOKING, never a meeting. Every occurrence is materialised as an ordinary
--     translation_room.translation_rooms row pointing back here through series_id. Everything
--     downstream of a room — billing, transcripts, artifacts, occupancy, the reminder sweep, the
--     AI pipeline — already assumes one room row is exactly one meeting, and this keeps that true.
--     Nothing downstream reads these columns.
--
--     The type/interval/by_weekdays/by_month_day quartet is deliberately wider than DAILY needs.
--     Only DAILY is materialised by the service today; WEEKLY and MONTHLY are already accepted by
--     the CHECK constraint so adding them later is application code and a UI control, not a second
--     migration against a table that by then holds production rows.
--
--   TIME
--     start_time_local + time_zone (IANA id, never a UTC offset) is the user's actual intent, and
--     it survives a tzdata rule change because the UTC instant is re-derived per occurrence at
--     materialisation time and written to translation_rooms.scheduled_at — which stays UTC exactly
--     as it always has been.
--
--   TERMINATION
--     ends_on_local_date is NOT NULL. An indefinite series generates rooms forever for workspaces
--     nobody will open again; the application defaults it to 30 days out and caps it at 365.

CREATE TABLE IF NOT EXISTS translation_room.translation_room_series (
    id uuid PRIMARY KEY DEFAULT uuidv7(),

    workspace_id uuid NOT NULL,
    host_id uuid NOT NULL,

    recurrence_type varchar(20) NOT NULL DEFAULT 'DAILY',
    recurrence_interval integer NOT NULL DEFAULT 1,
    recurrence_by_weekdays jsonb,
    recurrence_by_month_day smallint,

    start_time_local time without time zone NOT NULL,
    time_zone varchar(64) NOT NULL,

    starts_on_local_date date NOT NULL,
    ends_on_local_date date NOT NULL,

    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    materialized_through_local_date date,

    title varchar(255) NOT NULL,
    description text,
    translation_room_type varchar(20) NOT NULL,
    max_participants integer NOT NULL DEFAULT 0,
    source_language varchar(15) NOT NULL,
    target_languages jsonb NOT NULL DEFAULT '[]'::jsonb,
    settings jsonb NOT NULL DEFAULT '{}'::jsonb,
    invited_emails jsonb NOT NULL DEFAULT '[]'::jsonb,

    created_at timestamp NOT NULL DEFAULT now(),
    created_by uuid,
    updated_at timestamp NOT NULL DEFAULT now(),
    updated_by uuid,

    CONSTRAINT translation_room_series_recurrence_type_check
        CHECK (recurrence_type IN ('DAILY', 'WEEKLY', 'MONTHLY')),
    CONSTRAINT translation_room_series_status_check
        CHECK (status IN ('ACTIVE', 'CANCELLED', 'COMPLETED')),
    CONSTRAINT translation_room_series_interval_check
        CHECK (recurrence_interval >= 1),
    CONSTRAINT translation_room_series_month_day_check
        CHECK (recurrence_by_month_day IS NULL OR (recurrence_by_month_day BETWEEN 1 AND 31)),
    CONSTRAINT translation_room_series_date_order_check
        CHECK (ends_on_local_date >= starts_on_local_date)
);

COMMENT ON TABLE translation_room.translation_room_series IS
    'WT-327: a recurring booking rather than a meeting - each occurrence is materialised as an ordinary translation_rooms row linked by series_id';

CREATE INDEX IF NOT EXISTS translation_room_series_status_materialized_through_idx
    ON translation_room.translation_room_series (status, materialized_through_local_date);

CREATE INDEX IF NOT EXISTS translation_room_series_workspace_id_created_at_idx
    ON translation_room.translation_room_series (workspace_id, created_at);

ALTER TABLE translation_room.translation_rooms
    ADD COLUMN IF NOT EXISTS series_id uuid,
    ADD COLUMN IF NOT EXISTS series_occurrence_local_date date;

COMMENT ON COLUMN translation_room.translation_rooms.series_id IS
    'WT-327: the recurring series this room is an occurrence of, or NULL for a one-off room (which is every row that existed before this column).';
COMMENT ON COLUMN translation_room.translation_rooms.series_occurrence_local_date IS
    'WT-327: the calendar date, in the series own time zone, this occurrence was generated for.';

-- RESTRICT, not CASCADE: deleting a series must never take the meetings it produced — and their
-- transcripts, artifacts and billing records — with it.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'translation_rooms_series_id_fkey'
    ) THEN
        ALTER TABLE translation_room.translation_rooms
            ADD CONSTRAINT translation_rooms_series_id_fkey
            FOREIGN KEY (series_id)
            REFERENCES translation_room.translation_room_series (id)
            ON DELETE RESTRICT;
    END IF;
END $$;

-- THE idempotency guarantee of the materialisation sweep: one series holds at most one room per
-- local date, so a double-run, a restart mid-pass, or two service replicas sweeping at the same
-- moment cannot produce two rooms for the same day.
CREATE UNIQUE INDEX IF NOT EXISTS translation_rooms_series_id_occurrence_date_key
    ON translation_room.translation_rooms (series_id, series_occurrence_local_date)
    WHERE series_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS translation_rooms_series_id_scheduled_at_idx
    ON translation_room.translation_rooms (series_id, scheduled_at)
    WHERE series_id IS NOT NULL;
