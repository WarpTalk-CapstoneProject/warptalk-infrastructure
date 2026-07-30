-- Migration: 016-03-07-2026-enforce-single-active-subscription
-- Description: Enforce at most one active subscription per workspace at the database level.
--              "Active" is defined as end_date IS NULL (open-ended, currently running period).
--              Prevents two concurrently-active subscriptions being created for the same
--              workspace_id, whether by a race condition or an application-layer bug.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'subscription' 
          AND table_name = 'subscriptions' 
          AND column_name = 'end_date'
    ) THEN
        CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_one_active_per_workspace_idx
            ON subscription.subscriptions (workspace_id)
            WHERE end_date IS NULL;
    END IF;
END $$;
