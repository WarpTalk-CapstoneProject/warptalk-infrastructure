-- Rollback: 041-26-07-2026-phase3-contract-overage-settlement
-- Use only before production cutover or after taking a database backup.
-- This removes Phase 3 contract/overage/suspend primitives.

BEGIN;

DROP FUNCTION IF EXISTS subscription.settle_usage_charge(
    uuid,
    uuid,
    uuid,
    varchar,
    varchar,
    uuid,
    varchar,
    uuid,
    uuid,
    numeric,
    varchar,
    int,
    varchar,
    uuid,
    numeric,
    varchar,
    jsonb
);

DROP FUNCTION IF EXISTS subscription.resolve_contract_terms(uuid);

DROP INDEX IF EXISTS subscription.ux_subscriptions_trial_owner_domain;
DROP INDEX IF EXISTS subscription.ix_subscriptions_cycle_due;
DROP INDEX IF EXISTS subscription.ix_subscriptions_overdue_state;

ALTER TABLE subscription.subscriptions
    DROP CONSTRAINT IF EXISTS subscriptions_service_state_chk,
    DROP CONSTRAINT IF EXISTS subscriptions_suspended_reason_chk,
    DROP COLUMN IF EXISTS credits_per_cycle_override,
    DROP COLUMN IF EXISTS contract_price_vnd,
    DROP COLUMN IF EXISTS overage_cap_credits_override,
    DROP COLUMN IF EXISTS overage_price_per_credit_override,
    DROP COLUMN IF EXISTS invoice_terms_days_override,
    DROP COLUMN IF EXISTS billing_contact_email,
    DROP COLUMN IF EXISTS overage_credits_this_cycle,
    DROP COLUMN IF EXISTS overage_started_at,
    DROP COLUMN IF EXISTS service_state,
    DROP COLUMN IF EXISTS suspended_reason,
    DROP COLUMN IF EXISTS owner_email_domain;

COMMIT;
