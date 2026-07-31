-- Draft seed: Phase 3 billing demo state.
-- Apply only in local/staging demo databases, not production.

BEGIN;

INSERT INTO subscription.plans (
    id, name, slug, tier, price, billing_cycle, credits_per_cycle,
    overage_cap_credits, overage_price_per_credit, low_balance_threshold_credits,
    rollover_cap_credits, invoice_terms_days, invoice_grace_hours,
    max_participants, max_languages, voice_clone_enabled, ai_assistant_enabled, glossary_enabled, features
) VALUES (
    '12000000-0000-0000-0000-000000000041',
    'Phase 3 Demo Enterprise',
    'phase3-demo-enterprise',
    'enterprise',
    1000000,
    'monthly',
    100000,
    25000,
    4.0000,
    30000,
    10000,
    15,
    24,
    50,
    10,
    true,
    true,
    true,
    '{"phase":"3","purpose":"demo"}'::jsonb
)
ON CONFLICT (slug) DO UPDATE
SET price = EXCLUDED.price,
    credits_per_cycle = EXCLUDED.credits_per_cycle,
    overage_cap_credits = EXCLUDED.overage_cap_credits,
    overage_price_per_credit = EXCLUDED.overage_price_per_credit,
    low_balance_threshold_credits = EXCLUDED.low_balance_threshold_credits,
    rollover_cap_credits = EXCLUDED.rollover_cap_credits,
    invoice_terms_days = EXCLUDED.invoice_terms_days,
    invoice_grace_hours = EXCLUDED.invoice_grace_hours,
    updated_at = now();

INSERT INTO subscription.subscriptions (
    id, user_id, workspace_id, plan_id, status, credits_remaining, credits_used_this_cycle,
    current_period_start, current_period_end, is_active,
    overage_credits_this_cycle, overage_started_at, service_state, suspended_reason,
    billing_contact_email, owner_email_domain
) VALUES (
    '23000000-0000-0000-0000-000000000041',
    '33000000-0000-0000-0000-000000000041',
    '43000000-0000-0000-0000-000000000041',
    '12000000-0000-0000-0000-000000000041',
    'active',
    -5000,
    105000,
    now() - interval '1 month',
    now() + interval '1 day',
    true,
    5000,
    now() - interval '2 days',
    'in_overage',
    NULL,
    'finance@example.com',
    'example.com'
)
ON CONFLICT (workspace_id) WHERE is_active = true AND workspace_id IS NOT NULL DO UPDATE
SET credits_remaining = EXCLUDED.credits_remaining,
    credits_used_this_cycle = EXCLUDED.credits_used_this_cycle,
    overage_credits_this_cycle = EXCLUDED.overage_credits_this_cycle,
    overage_started_at = EXCLUDED.overage_started_at,
    service_state = EXCLUDED.service_state,
    suspended_reason = EXCLUDED.suspended_reason,
    updated_at = now();

INSERT INTO subscription.payments (
    id, subscription_id, user_id, amount, tax_amount, total_amount,
    currency, payment_method, provider, provider_transaction_id, status,
    provider_metadata, created_at, updated_at
) VALUES (
    '24000000-0000-0000-0000-000000000041',
    '23000000-0000-0000-0000-000000000041',
    '33000000-0000-0000-0000-000000000041',
    1020000,
    102000,
    1122000,
    'VND',
    'invoice',
    'manual',
    'phase3-demo-cycle',
    'pending',
    '{"phase":"3","purpose":"invoice_overdue_demo"}'::jsonb,
    now() - interval '20 days',
    now() - interval '20 days'
)
ON CONFLICT (id) DO UPDATE
SET status = EXCLUDED.status,
    total_amount = EXCLUDED.total_amount,
    updated_at = now();

INSERT INTO subscription.invoices (
    id, payment_id, user_id, invoice_number, subtotal, tax, total,
    currency, status, line_items, issued_at, due_at, created_at
) VALUES (
    '25000000-0000-0000-0000-000000000041',
    '24000000-0000-0000-0000-000000000041',
    '33000000-0000-0000-0000-000000000041',
    'PHASE3-DEMO-OVERDUE',
    1020000,
    102000,
    1122000,
    'VND',
    'issued',
    '[{"name":"Contract base","amount":1000000},{"name":"Overage credits","quantity":5000,"unit_price":4,"amount":20000}]'::jsonb,
    now() - interval '20 days',
    now() - interval '5 days',
    now() - interval '20 days'
)
ON CONFLICT (invoice_number) DO UPDATE
SET status = EXCLUDED.status,
    due_at = EXCLUDED.due_at,
    total = EXCLUDED.total;

COMMIT;
