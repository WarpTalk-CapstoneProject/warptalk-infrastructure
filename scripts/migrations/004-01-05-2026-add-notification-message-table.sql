-- Migration: 004-01-05-2026-add-notification-message-table
-- Description: Create the notification_messages table with partitions, composite indexes and grants

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
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE IF NOT EXISTS notification.notification_messages_y2025 PARTITION OF notification.notification_messages
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE IF NOT EXISTS notification.notification_messages_y2026 PARTITION OF notification.notification_messages
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE IF NOT EXISTS notification.notification_messages_y2027 PARTITION OF notification.notification_messages
    FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');
CREATE TABLE IF NOT EXISTS notification.notification_messages_default PARTITION OF notification.notification_messages DEFAULT;

CREATE INDEX IF NOT EXISTS idx_notif_msgs_user_unread ON notification.notification_messages (user_id, created_at DESC) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notif_msgs_created_at ON notification.notification_messages (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_msgs_user ON notification.notification_messages (user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON notification.notification_messages TO notif_svc;
