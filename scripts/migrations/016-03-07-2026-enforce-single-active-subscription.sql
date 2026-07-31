-- Migration: 016-03-07-2026-enforce-single-active-subscription
-- Description: Enforce at most one active subscription per workspace at the database level.
--              "Active" follows the canonical subscription.is_active flag.
--              Prevents two concurrently-active subscriptions being created for the same
--              workspace_id, whether by a race condition or an application-layer bug.

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_one_active_per_workspace_idx
    ON subscription.subscriptions (workspace_id)
    WHERE is_active = true AND workspace_id IS NOT NULL;
