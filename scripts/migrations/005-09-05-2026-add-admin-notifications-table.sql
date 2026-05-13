-- Migration: 005-09-05-2026-add-admin-notifications-table
-- Description: Create the admin_notifications table for Admin Notification Management (WT-58)

CREATE SCHEMA IF NOT EXISTS notification;

CREATE TABLE notification.admin_notifications (
    id uuid NOT NULL DEFAULT (uuidv7()),
    title character varying(255) NOT NULL,
    content text NOT NULL,
    type character varying(50) NOT NULL,
    payload jsonb NOT NULL DEFAULT ('{}'::jsonb),
    target_audience_mode character varying(50) NOT NULL,
    target_audience_data jsonb NOT NULL DEFAULT ('{}'::jsonb),
    status character varying(50) NOT NULL,
    created_by uuid NOT NULL,
    updated_by uuid,
    created_at timestamp with time zone NOT NULL DEFAULT (now()),
    updated_at timestamp with time zone NOT NULL DEFAULT (now()),
    PRIMARY KEY (id)
);

-- Basic Indexes
CREATE INDEX idx_admin_notifications_created_at ON notification.admin_notifications (created_at DESC);
CREATE INDEX idx_admin_notifications_created_by ON notification.admin_notifications (created_by);
CREATE INDEX idx_admin_notifications_status ON notification.admin_notifications (status);

-- Query Optimization: Composite index for filtering by type/status and sorting
CREATE INDEX idx_admin_notif_list_opt ON notification.admin_notifications (type, status, created_at DESC);

-- Search Support: Trigram index for fast title keyword search (ILIKE support)
CREATE INDEX idx_admin_notif_title_trgm ON notification.admin_notifications USING gin (title gin_trgm_ops);
