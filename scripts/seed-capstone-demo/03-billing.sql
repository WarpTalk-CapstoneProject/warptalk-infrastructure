-- ====================================================================
-- WarpTalk capstone demo seed — PART 3/5: billing
-- Target database: warptalk_billing
--
-- Gives the demo workspace a LIVE enterprise subscription. This is not
-- decoration: WT-515 made the product a hard paywall, and
-- WorkspaceDirectoryService.ValidateMeetingCreationAsync denies meeting
-- creation whenever the entitlement snapshot says
-- has_active_subscription = false. The web [workspaceSlug] layout renders
-- WorkspacePaywall in the same case.
--
-- GatherAsync decides "live" with FOUR conditions, all of which must hold:
--     subscription != null
--  && subscription.IsActive
--  && subscription.Status == 'active'
--  && subscription.CurrentPeriodEnd >= now
-- A row with is_active = t but status = 'cancelled' reads as unpaid. That is
-- exactly the shape that broke the previous demo workspace on 2026-08-16.
--
-- WRITING THIS ROW IS NOT ENOUGH. The snapshot workspace enforces from is
-- only rewritten when billing publishes billing.entitlements_changed, and
-- there is no scheduled backfill. Finish with step 6 of README.md.
-- Do NOT hand-write workspace.workspace_entitlement_snapshots — that creates a
-- second source of truth that drifts from EntitlementResolver.
--
-- Idempotent: safe to re-run.
-- ====================================================================

\set ON_ERROR_STOP on

\set workspace_id   '019f1a00-0de0-7000-9200-0000000000aa'
\set owner_id       '019f1a00-0de0-7000-9200-000000000001'
\set subscription_id '019f1a00-0de0-7000-9200-0000000000a1'

BEGIN;

-- ── 1. Resolve the enterprise plan by slug ──────────────────────────
-- By slug, not by a hardcoded id: plan ids differ per environment. On prod
-- 2026-08-19 'enterprise' is 019ec641-9776-7d50-b2b9-9edb93a46d24 with
-- max_participants 500, max_languages 3, max_active_rooms 50, and
-- voice_clone / ai_assistant / glossary all enabled — which is what makes the
-- demo's headline features reachable.
CREATE TEMP TABLE demo_plan AS
SELECT id, slug, credits_per_cycle
FROM subscription.plans
WHERE slug = 'enterprise' AND is_active AND deleted_at IS NULL
LIMIT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM demo_plan) THEN
        RAISE EXCEPTION 'No active plan with slug ''enterprise'' in subscription.plans. '
            'Seed the plans first (see service-migrations/billing/002-seed-default-plans.sql).';
    END IF;
END $$;

-- ── 2. Subscription ─────────────────────────────────────────────────
-- Period deliberately starts in the past and ends a month out, so the Billing
-- screen shows a cycle in progress rather than one that begins today.
-- credits_used_this_cycle is non-zero for the same reason: an untouched quota
-- bar reads as "nothing has ever run here".
INSERT INTO subscription.subscriptions (
    id, user_id, workspace_id, plan_id, status,
    credits_remaining, credits_used_this_cycle, overage_credits_this_cycle,
    current_period_start, current_period_end,
    auto_renew, is_active, service_state,
    owner_email_domain, billing_contact_email,
    created_at, created_by, updated_at, updated_by
)
SELECT
    :'subscription_id', :'owner_id', :'workspace_id', p.id, 'active',
    p.credits_per_cycle - 17550, 17550, 0,
    NOW() - INTERVAL '5 days', NOW() + INTERVAL '25 days',
    true, true, 'healthy',
    'warptalk.vn', 'owner@warptalk.vn',
    NOW(), :'owner_id', NOW(), :'owner_id'
FROM demo_plan AS p
ON CONFLICT (id) DO UPDATE SET
    plan_id                 = EXCLUDED.plan_id,
    status                  = 'active',
    is_active               = true,
    service_state           = 'healthy',
    suspended_reason        = NULL,
    cancelled_at            = NULL,
    cancellation_reason     = NULL,
    credits_remaining       = EXCLUDED.credits_remaining,
    credits_used_this_cycle = EXCLUDED.credits_used_this_cycle,
    current_period_start    = EXCLUDED.current_period_start,
    current_period_end      = EXCLUDED.current_period_end,
    auto_renew              = true,
    deleted_at              = NULL,
    updated_at              = NOW();

-- Guard: a second, older subscription row on the same workspace can win the
-- resolver's lookup and silently reinstate the paywall.
DO $assert$
DECLARE
    v_extra int;
BEGIN
    SELECT count(*) INTO v_extra
    FROM subscription.subscriptions
    WHERE workspace_id = '019f1a00-0de0-7000-9200-0000000000aa'
      AND id <> '019f1a00-0de0-7000-9200-0000000000a1'
      AND deleted_at IS NULL;

    IF v_extra > 0 THEN
        RAISE EXCEPTION 'Found % other subscription row(s) on the demo workspace. '
            'Resolve which one should win before continuing.', v_extra;
    END IF;
END $assert$;

-- ── 3. Assert the four liveness conditions ──────────────────────────
DO $assert$
DECLARE
    v_ok boolean;
BEGIN
    SELECT s.is_active
           AND s.status = 'active'
           AND s.current_period_end >= NOW()
           AND s.deleted_at IS NULL
    INTO v_ok
    FROM subscription.subscriptions AS s
    WHERE s.id = '019f1a00-0de0-7000-9200-0000000000a1';

    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'Demo subscription does not satisfy all four liveness conditions '
            'GatherAsync tests; the workspace would still read as unpaid.';
    END IF;
END $assert$;

COMMIT;

\echo ''
\echo '--- Demo subscription ---'
SELECT s.id, p.slug AS plan, s.status, s.is_active, s.credits_remaining,
       s.credits_used_this_cycle, s.current_period_start, s.current_period_end
FROM subscription.subscriptions AS s
JOIN subscription.plans AS p ON p.id = s.plan_id
WHERE s.workspace_id = :'workspace_id';

\echo '--- REMINDER: the snapshot is still stale until billing republishes. ---'
\echo '--- Run step 6 in README.md (save Workspace Settings via the API). ---'
