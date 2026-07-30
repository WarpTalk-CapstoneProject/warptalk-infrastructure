-- Phase 2: durable Billing event delivery and consumer deduplication.
BEGIN;

CREATE TABLE IF NOT EXISTS subscription.outbox_messages (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    event_type VARCHAR(150) NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    occurred_at TIMESTAMPTZ NOT NULL,
    producer VARCHAR(100) NOT NULL,
    correlation_id VARCHAR(100),
    causation_id VARCHAR(100),
    workspace_id UUID,
    payload_json JSONB NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    locked_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_outbox_messages_dispatch
    ON subscription.outbox_messages (published_at, available_at, created_at);

CREATE TABLE IF NOT EXISTS subscription.inbox_messages (
    event_id UUID NOT NULL,
    consumer VARCHAR(150) NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type VARCHAR(150) NOT NULL,
    last_error TEXT,
    PRIMARY KEY (event_id, consumer)
);

COMMIT;
