-- Smoke: Phase 3 settlement overage + idempotency.
-- Run:
--   docker exec -i warptalk-postgres psql -U postgres -d warptalk -v ON_ERROR_STOP=1 < scripts/smoke/041-phase3-settlement-smoke.sql

BEGIN;

INSERT INTO subscription.plans (
    id, name, slug, tier, price, billing_cycle, credits_per_cycle,
    overage_cap_credits, overage_price_per_credit, low_balance_threshold_credits,
    rollover_cap_credits, invoice_terms_days, invoice_grace_hours,
    max_participants, max_languages, features
) VALUES (
    '10000000-0000-0000-0000-000000000041', 'Phase 3 Smoke', 'phase3-smoke-041', 'enterprise', 1000000, 'monthly', 1000,
    1000, 4.0000, 2000, 100, 15, 360,
    10, 5, '{}'::jsonb
);

INSERT INTO subscription.subscriptions (
    id, user_id, workspace_id, plan_id, status, credits_remaining, credits_used_this_cycle,
    current_period_start, current_period_end, is_active
) VALUES (
    '20000000-0000-0000-0000-000000000041',
    '30000000-0000-0000-0000-000000000041',
    '40000000-0000-0000-0000-000000000041',
    '10000000-0000-0000-0000-000000000041',
    'active', 100, 0,
    now() - interval '1 month', now() + interval '1 month', true
);

SELECT applied, balance_after, service_state, suspended_reason
FROM subscription.settle_usage_charge(
    '20000000-0000-0000-0000-000000000041',
    '30000000-0000-0000-0000-000000000041',
    '40000000-0000-0000-0000-000000000041',
    'AI_ASSISTANT',
    'AI_ASSISTANT',
    NULL,
    'usage',
    NULL,
    NULL,
    250,
    'token_out',
    250,
    'phase3-smoke-idempotency',
    NULL,
    1.000000,
    'VND',
    '{"source":"phase3-smoke"}'::jsonb
);

SELECT applied, balance_after, service_state, suspended_reason
FROM subscription.settle_usage_charge(
    '20000000-0000-0000-0000-000000000041',
    '30000000-0000-0000-0000-000000000041',
    '40000000-0000-0000-0000-000000000041',
    'AI_ASSISTANT',
    'AI_ASSISTANT',
    NULL,
    'usage',
    NULL,
    NULL,
    250,
    'token_out',
    250,
    'phase3-smoke-idempotency',
    NULL,
    1.000000,
    'VND',
    '{"source":"phase3-smoke"}'::jsonb
);

SELECT credits_remaining, credits_used_this_cycle, overage_credits_this_cycle, service_state, suspended_reason
FROM subscription.subscriptions
WHERE id = '20000000-0000-0000-0000-000000000041';

ROLLBACK;
