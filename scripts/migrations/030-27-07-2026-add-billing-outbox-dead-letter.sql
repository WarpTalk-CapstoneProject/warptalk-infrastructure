BEGIN;

ALTER TABLE subscription.outbox_messages
    ADD COLUMN IF NOT EXISTS dead_lettered_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_outbox_messages_dead_letter
    ON subscription.outbox_messages (dead_lettered_at, created_at)
    WHERE dead_lettered_at IS NOT NULL;

COMMIT;
