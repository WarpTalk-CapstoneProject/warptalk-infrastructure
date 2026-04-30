-- Migration: 004-01-05-2026-add-notification-message-table
-- Description: Create the notification_messages table

CREATE TABLE IF NOT EXISTS notification.notification_messages (
    id uuid NOT NULL DEFAULT (uuid_generate_v7()),
    user_id uuid NOT NULL,
    type character varying(50) NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    action_url character varying(500),
    payload_json jsonb NOT NULL DEFAULT ('{}'::jsonb),
    is_read boolean NOT NULL DEFAULT FALSE,
    read_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT (now()),
    CONSTRAINT notification_messages_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_notif_msgs_created_at ON notification.notification_messages (created_at);
CREATE INDEX IF NOT EXISTS idx_notif_msgs_is_read ON notification.notification_messages (is_read);
CREATE INDEX IF NOT EXISTS idx_notif_msgs_user ON notification.notification_messages (user_id);
