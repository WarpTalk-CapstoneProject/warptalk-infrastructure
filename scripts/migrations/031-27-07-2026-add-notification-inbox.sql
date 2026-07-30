BEGIN;

CREATE TABLE IF NOT EXISTS notification.inbox_messages
(
    event_id uuid NOT NULL,
    consumer varchar(150) NOT NULL,
    event_type varchar(150) NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inbox_messages_pkey PRIMARY KEY (event_id, consumer)
);

CREATE INDEX IF NOT EXISTS idx_notification_inbox_processed
    ON notification.inbox_messages (processed_at DESC);

COMMIT;
